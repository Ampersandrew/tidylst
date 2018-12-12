package LstTidy::Convert;

use strict;
use warnings;

=head2 convertEntities

   This subroutine takes a single string and converts all special characters in
   it to an ascii equivalent. It returns a modified copy of the input.

=cut

sub convertEntities {
   my ($line) = @_;

   $line =~ s/\x82/,/g;
   $line =~ s/\x84/,,/g;
   $line =~ s/\x85/.../g;
   $line =~ s/\x88/^/g;
   $line =~ s/\x8B/</g;
   $line =~ s/\x8C/Oe/g;
   $line =~ s/\x91/\'/g;
   $line =~ s/\x92/\'/g;
   $line =~ s/\x93/\"/g;
   $line =~ s/\x94/\"/g;
   $line =~ s/\x95/*/g;
   $line =~ s/\x96/-/g;
   $line =~ s/\x97/-/g;
   $line =~ s-\x98-<sup>~</sup>-g;
   $line =~ s-\x99-<sup>TM</sup>-g;
   $line =~ s/\x9B/>/g;
   $line =~ s/\x9C/oe/g;

   return $line;
};

=head2 convertPreSpellType

   PRESPELLTYPE was previously separated with commas, now uses =

   Takes the value (following the :), the linetype, the file and the line
   number. It returns the modified value.

=cut

sub convertPreSpellType {

   my ($tag) = @_;
   
   if (LstTidy::Options::isConversionActive('ALL:PRESPELLTYPE Syntax')) {

      if ($tag->tag() eq 'PRESPELLTYPE') {

         if ($tag->value() =~ /^([^\d]+),(\d+),(\d+)/) {
            my ($spelltype, $num_spells, $num_levels) = ($1, $2, $3);

            my $value = "$num_spells";

            # Common homebrew mistake is to include Arcade|Divine, since the
            # 5.8 documentation had an example that showed this. Might
            # as well handle it while I'm here.
            my @spelltypes = split(/\|/,$spelltype);

            foreach my $st (@spelltypes) {
               $value .= ",$st=$num_levels";
            }

            LstTidy::LogFactory::GetLogger()->notice(
               qq{Invalid standalone PRESPELLTYPE tag "PRESPELLTYPE:${value}" found and converted in } . $tag->linetype(),
               $tag->file(),
               $tag->line()
            );

            $tag->value($value);
         }

      # Continuing the fix - fix it anywhere. This is meant to address PRE tags
      # that are on the end of other tags or in PREMULTS.
      # I'll leave out the pipe-delimited error here, since it's more likely
      # to end up with confusion when the tag isn't standalone.

      } elsif ($tag->value() =~ /PRESPELLTYPE:([^\d]+),(\d+),(\d+)/) {

         $tag->value($tag->value() =~ s/PRESPELLTYPE:([^\d,]+),(\d+),(\d+)/PRESPELLTYPE:$2,$1=$3/gr);

         LstTidy::LogFactory::GetLogger()->notice(
            qq{Invalid embedded PRESPELLTYPE tag "} . $tag->fullTag() . q{" found and converted } . $tag->linetype() . q{.},
            $tag->file(),
            $tag->line()
         );
      }
   }
}

=head2 convertAddTags
=cut
sub convertAddTags {
   my ($tag) = @_;

   my ($type, $addTag, $theRest, $addCount) = LstTidy::Parse::parseAddTag( $tag->fullTag );
   # Return code 0 = no valid ADD tag found,
   #             1 = old format token ADD tag found,
   #             2 = old format adlib ADD tag found.
   #             3 = 5.12 format ADD tag, using known token.
   #             4 = 5.12 format ADD tag, not using token.

   if ($type) {
      # It's a ADD:token tag
      if ( $type == 1) {
         $tag->tag($addTag);
         $tag->value("($theRest)$addCount");
      }

      if (($type == 1 || $type == 2) && LstTidy::Options::isConversionActive('ALL:ADD Syntax Fix'))
      {
         $tag->tag("ADD:");
         $addTag =~ s/ADD://;
         $tag->value("$addTag|$addCount|$theRest");
      }

   } else {
      if ( index( $tag->fullTag, '#' ) != 0 ) {

         LstTidy::LogFactory::getLogger->notice(
            qq{Invalid ADD tag "} . $tag->fullTag . q{" found in } . $tag->linetype,
            $tag->file,
            $tag->line
         );

         LstTidy::Report::incCountInvalidTags($tag->linetype, $addTag); 
         $no_more_error = 1;
      }
   }
}



1;


__END__
