#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(abs_path $0) . '/lib';

use LstTidy::Log;
use LstTidy::LogFactory;
use LstTidy::LogHeader;
use LstTidy::Tag;

use LstTidy::Options qw(getOption);

# Move these into Parse.pm, or Validate.pm whenever the code using them is moved.
my @validSystemAlignments = LstTidy::Parse::getValidSystemArr('alignments');
my @validSystemStats      = LstTidy::Parse::getValidSystemArr('stats');

# Limited choice tags
my %tag_fix_value = (
   ACHECK               => { YES => 1, NO => 1, WEIGHT => 1, PROFICIENT => 1, DOUBLE => 1 },
   ALIGN                => { map { $_ => 1 } @validSystemAlignments },
   APPLY                => { INSTANT => 1, PERMANENT => 1 },
   BONUSSPELLSTAT       => { map { $_ => 1 } ( @validSystemStats, 'NONE' ) },
   DESCISIP             => { YES => 1, NO => 1 },
   EXCLUSIVE            => { YES => 1, NO => 1 },
   FORMATCAT            => { FRONT => 1, MIDDLE => 1, PARENS => 1 },
   FREE                 => { YES => 1, NO => 1 },
   KEYSTAT              => { map { $_ => 1 } @validSystemStats },
   HASSUBCLASS          => { YES => 1, NO => 1 },
   ALLOWBASECLASS       => { YES => 1, NO => 1 },
   HASSUBSTITUTIONLEVEL => { YES => 1, NO => 1 },
   ISD20                => { YES => 1, NO => 1 },
   ISLICENSED           => { YES => 1, NO => 1 },
   ISOGL                => { YES => 1, NO => 1 },
   ISMATURE             => { YES => 1, NO => 1 },
   MEMORIZE             => { YES => 1, NO => 1 },
   MULT                 => { YES => 1, NO => 1 },
   MODS                 => { YES => 1, NO => 1, REQUIRED => 1 },
   MODTOSKILLS          => { YES => 1, NO => 1 },
   NAMEISPI             => { YES => 1, NO => 1 },
   RACIAL               => { YES => 1, NO => 1 },
   REMOVABLE            => { YES => 1, NO => 1 },
   RESIZE               => { YES => 1, NO => 1 },
   PREALIGN             => { map { $_ => 1 } @validSystemAlignments }, 
   PRESPELLBOOK         => { YES => 1, NO => 1 },
   SHOWINMENU           => { YES => 1, NO => 1 },
   STACK                => { YES => 1, NO => 1 },
   SPELLBOOK            => { YES => 1, NO => 1 },
   SPELLSTAT            => { map { $_ => 1 } ( @validSystemStats, 'SPELL', 'NONE', 'OTHER' ) },
   TIMEUNIT             => { map { $_ => 1 } qw( Year Month Week Day Hour Minute Round Encounter Charges ) },
   USEUNTRAINED         => { YES => 1, NO => 1 },
   USEMASTERSKILL       => { YES => 1, NO => 1 },
   VISIBLE              => { map { $_ => 1 } qw( YES NO EXPORT DISPLAY QUALIFY CSHEET GUI ALWAYS ) },
);

# This hash is used to convert 1 character choices to proper fix values.
my %tag_proper_value_for = (
   'Y'     =>  'YES',
   'N'     =>  'NO',
   'W'     =>  'WEIGHT',
   'Q'     =>  'QUALIFY',
   'P'     =>  'PROFICIENT',
   'R'     =>  'REQUIRED',
   'true'  =>  'YES',
   'false' =>  'NO',
);

# [ 832171 ] AUTO:* needs to be separate tags
my @token_AUTO_tag = (
   'ARMORPROF',
   'EQUIP',
   'FEAT',
   'LANG',
   'SHIELDPROF',
   'WEAPONPROF',
);


=head2 parse_tag

   The most common use of this function is for the addition, conversion or
   removal of tags.

   Paramter: $tagText  Text to parse
             $linetype  Type for the current line
             $file      Name of the current file
             $line      Number of the current line

   Return:   in scalar context, return $tag
             in array context, return ($tag, $value)
=cut

sub parse_tag {

   my ($tagText, $linetype, $file, $line) = @_;

   my $no_more_error = 0;  # Set to 1 if no more error must be displayed.

   my $logger = LstTidy::LogFactory::GetLogger();

   # We remove the enclosing quotes if any
   if ($tagText =~ s/^"(.*)"$/$1/) {
      $logger->warning( qq{Removing quotes around the '$tagText' tag}, $file, $line)
   }

   # Is this a pragma?
   if ( $tagText =~ /^(\#.*?):(.*)/ && LstTidy::Reformat::isValidTag($linetype, $1)) {
      return wantarray ? ( $1, $2 ) : $1
   }

   # Return already if no text to parse (comment)
   if (length $tagText == 0 || $tagText =~ /^\s*\#/) {
      return wantarray ? ( "", "" ) : ""
   }

   # Remove any spaces before and after the tag
   $tagText =~ s/^\s+//;
   $tagText =~ s/\s+$//;

   my $tag =  LstTidy::Tag->new(
      fullTag  => $tagText,
      lineType => $linetype,
      file     => $file,
      line     => $line,
   );

   # All PCGen tags should have at least TAG_NAME:TAG_VALUE (Some rare tags
   # have two colons). Anything without a tag value is an anomaly. The only
   # exception to this rule is LICENSE that can be used without a value to
   # display an empty line.

   if ( (!defined $tag->value || $tag->value eq q{}) && $tagText ne 'LICENSE:') {
      $logger->warning(
         qq(The tag "$tagText" is missing a value (or you forgot a : somewhere)),
         $file,
         $line
      );

      # We set the value to prevent further errors
      $tag->value(q{});
   }

   # [ 1387361 ] No KIT STARTPACK entry for \"KIT:xxx\"
   # STARTPACK lines in Kit files weren't getting added to $valid_entities. If
   # the verify flag is set and they aren't added to valid_entities, each Kit
   # will cause a spurious error. I've added them to valid entities to prevent
   # that.
   if ($tag->id eq 'STARTPACK') {
      my $value  = $tag->value;
      LstTidy::Validate::setEntityValid('KIT STARTPACK', "KIT:$value");
      LstTidy::Validate::setEntityValid('KIT STARTPACK', "$value");
   }
   
   if ( $tag->fullTag =~ /PRESPELLTYPE:([^\d]+),(\d+),(\d+)/) {
      LstTidy::Convert::convertPreSpellType($tag);
   }

   # Special cases like ADD:... and BONUS:...
   if ( $tag->id eq 'ADD' ) {
      LstTidy::Convert::convertAddTags($tag);
   }

   # [ 832171 ] AUTO:* needs to be separate tags
   if ( $tag->id eq 'AUTO' ) {
      LstTidy::Parse::parseAutoTag($tag);
   }

   if ( $tag->id eq 'BONUS' ) {
      LstTidy::Parse::parseSubTag($tag);
   }

   if ( $tag->id eq 'PROFICIENCY' ) {
      LstTidy::Parse::parseSubTag($tag);
   }

   if ( $tag->id eq 'QUALIFY' ) {
      LstTidy::Parse::parseSubTag($tag);
   }

   if ( $tag->id eq 'SPELLLEVEL' ) {
      LstTidy::Parse::parseSubTag($tag);
   }

   if ( $tag->id eq 'SPELLKNOWN' ) {
      LstTidy::Parse::parseSubTag($tag);
   }

   if ( defined $tag->value && $tag->value =~ /^.CLEAR/i ) {
      LstTidy::Validate::validateClearTag($tag);
   }

   # ===============================================================================================


   if ( !$tag->noMoreErrors && ! LstTidy::Reformat::isValidTag($tag->linetype, $tag->id) && index( $tag->fullTag, '#' ) != 0 ) {

      my $doWarn = 1;

      if ($tagText =~ /^ADD:([^\(\|]+)[\|\(]+/) {
         my $tagText = ($1);
         if (LstTidy::Reformat::isValidTag($tag->linetype, "ADD:$tagText")) {
            $doWarn = 0;
         }
      }

      if ($doWarn) {
         $logger->notice(
            qq{The tag "} . $tag->id . q{" from "} . $tagText . q{" is not in the } . $linetype . q{ tag list\n},

            $file,
            $line
         );
         LstTidy::Report::incCountInvalidTags($tag->linetype, $tag->realId); 
      }

   } elsif (LstTidy::Reformat::isValidTag($tag->linetype, $tag->id)) {

      # Statistic gathering
      LstTidy::Report::incCountValidTags($tag->linetype, $tag->realId);
   }

        # Check and reformat the values for the tags with
        # only a limited number of values.

        if ( exists $tag_fix_value{$tag->id} ) {

           # All the limited value are uppercase except the alignment value 'Deity'
           my $newvalue = uc($tag->value);
           my $is_valid = 1;

           # Special treament for the ALIGN tag
           if ( $tag->id eq 'ALIGN' || $tag->id eq 'PREALIGN' ) {
              # It is possible for the ALIGN and PREALIGN tags to have more then
              # one value

              # ALIGN use | for separator, PREALIGN use ,
              my $slip_patern = $tag->id eq 'PREALIGN' ? qr{[,]}xms : qr{[|]}xms;

              for my $align (split $slip_patern, $newvalue) {

                 if ( $align eq 'DEITY' ) { 
                    $align = 'Deity'; 
                 }

                 # Is it a number?
                 my ($number) = $align =~ / \A (\d+) \z /xms;

                 if ( defined $number && $number >= 0 && $number < scalar @validSystemAlignments) {
                    $align = $validSystemAlignments[$number];
                    $newvalue =~ s{ (?<! \d ) ($number) (?! \d ) }{$align}xms;
                 }

                 # Is it a valid alignment?
                 if (!exists $tag_fix_value{$tag->id}{$align}) {
                    $logger->notice(
                       qq{Invalid value "$align" for tag "} . $tag->realId . q{"},
                       $file,
                       $line
                    );
                    $is_valid = 0;
                 }
              }
           } else {

                # Standerdize the YES NO and other such tags
                if ( exists $tag_proper_value_for{$newvalue} ) {
                        $newvalue = $tag_proper_value_for{$newvalue};
                }

                # Is this a proper value for the tag?
                if ( !exists $tag_fix_value{$tag->id}{$newvalue} ) {
                   $logger->notice(
                      qq{Invalid value "} . $tag->value . q{" for tag "} . $tag->realId . q{"},
                      $file,
                      $line
                   );
                   $is_valid = 0;
                }
             }



                # Was the tag changed ?
                if ( $is_valid && $tag->value ne $newvalue && !( $tag->id eq 'ALIGN' || $tag->id eq 'PREALIGN' )) {
                   $logger->warning(
                      qq{Replaced "} . $tag->origTag . q{" by "} . $tag->realId . qq{:$newvalue"},
                      $file,
                      $line
                   );
                   $tag->value = $newvalue;
                }
        }

        ############################################################
        ######################## Conversion ########################
        # We manipulate the tag here
        additionnal_tag_parsing( $tag->realId, $tag->value, $tag->linetype, $file, $line );

        ############################################################
        # We call the validating function if needed
        if (getOption('xcheck')) {
           validate_tag($tag->realId, $tag->value, $tag->linetype, $file, $line)
        };

        # If there is already a :  in the tag name, no need to add one more
        my $need_sep = index( $tag->realId, ':' ) == -1 ? q{:} : q{};

        if ($tag->value eq q{}) {
           $logger->debug(qq{parse_tag: $tagText}, $file, $line)
        };

        # We change the tagText value from the caller
        # This is very ugly but it gets th job done
        $_[0] = $tag->realId;
        $_[0] .= $need_sep . $tag->value if defined $tag->value;

        # Return the tag
        wantarray ? ( $tag->realId, $tag->value ) : $tag->realId;

}
