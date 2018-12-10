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

   my ($value, $linetype, $file, $line) = @_;

   if ($value =~ /^([^\d]+),(\d+),(\d+)/) {
      my ($spelltype, $num_spells, $num_levels) = ($1, $2, $3);

      $value = "$num_spells";

      # Common homebrew mistake is to include Arcade|Divine, since the
      # 5.8 documentation had an example that showed this. Might
      # as well handle it while I'm here.
      my @spelltypes = split(/\|/,$spelltype);

      foreach my $st (@spelltypes) {
         $value .= ",$st=$num_levels";
      }

      LstTidy::LogFactory::GetLogger()->notice(
         qq{Invalid standalone PRESPELLTYPE tag "PRESPELLTYPE:${value}" found and converted in $linetype.},
         $file,
         $line
      );
   }

   return $value;
}

1;


__END__
