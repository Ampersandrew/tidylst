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

my %token_BONUS_tag = map { $_ => 1 } (
   'ABILITYPOOL',
   'CASTERLEVEL',
   'CHECKS',
   'COMBAT',
   'CONCENTRATION',
   'DAMAGE',
   'DC',
   'DOMAIN',
   'DR',
   'EQM',
   'EQMARMOR',
   'EQMWEAPON',
   'ESIZE',
   'FEAT',
   'FOLLOWERS',
   'HD',
   'HP',
   'ITEMCOST',
   'LANGUAGES',
   'MISC',
   'MONSKILLPTS',
   'MOVE',
   'MOVEADD',
   'MOVEMULT',
   'POSTRANGEADD',
   'POSTMOVEADD',
   'PCLEVEL',
   'RANGEADD',
   'RANGEMULT',
   'REPUTATION',
   'SIZEMOD',
   'SAVE',
   'SKILL',
   'SITUATION',
   'SKILLPOINTS',
   'SKILLPOOL',
   'SKILLRANK',
   'SLOTS',
   'SPELL',
   'SPECIALTYSPELLKNOWN',
   'SPELLCAST',
   'SPELLCASTMULT',
   'SPELLKNOWN',
   'VISION',
   'STAT',
   'TOHIT',
   'UDAM',
   'VAR',
   'WEAPON',
   'WEAPONPROF',
   'WIELDCATEGORY',
);

my %token_PROFICIENCY_tag = map { $_ => 1 } (
   'WEAPON',
   'ARMOR',
   'SHIELD',
);

my %token_QUALIFY_tag = map { $_ => 1 } (
   'ABILITY',
   'CLASS',
   'DEITY',
   'DOMAIN',
   'EQUIPMENT',
   'EQMOD',
   'FEAT',
   'RACE',
   'SPELL',
   'SKILL',
   'TEMPLATE',
   'WEAPONPROF',
);


=head2 parse_tag

   The most common use of this function is for the addition, conversion or
   removal of tags.

   Paramter: $tag_text  Text to parse
             $linetype  Type for the current line
             $file      Name of the current file
             $line      Number of the current line

   Return:   in scalar context, return $tag
             in array context, return ($tag, $value)
=cut

sub parse_tag {

   my ($tag_text, $linetype, $file, $line) = @_;

   my $no_more_error = 0;  # Set to 1 if no more error must be displayed.

   my $logger = LstTidy::LogFactory::GetLogger();

   # We remove the enclosing quotes if any
   if ($tag_text =~ s/^"(.*)"$/$1/) {
      $logger->warning( qq{Removing quotes around the '$tag_text' tag}, $file, $line)
   }

   # Is this a pragma?
   if ( $tag_text =~ /^(\#.*?):(.*)/ && LstTidy::Reformat::isValidTag($linetype, $1)) {
      return wantarray ? ( $1, $2 ) : $1
   }

   # Return already if no text to parse (comment)
   if (length $tag_text == 0 || $tag_text =~ /^\s*\#/) {
      return wantarray ? ( "", "" ) : ""
   }

   # Remove any spaces before and after the tag
   $tag_text =~ s/^\s+//;
   $tag_text =~ s/\s+$//;

   my $tag =  LstTidy::Tag->new(
      tagValue => $tag_text,
      linetype => $linetype,
      file     => $file,
      line     => $line,
   );

   # All PCGen tags should have at least TAG_NAME:TAG_VALUE (Some rare tags
   # have two colons). Anything without a tag value is an anomaly. The only
   # exception to this rule is LICENSE that can be used without a value to
   # display an empty line.

   if ( (!defined $tag->value() || $tag->value() eq q{}) && $tag_text ne 'LICENSE:') {
      $logger->warning(
         qq(The tag "$tag_text" is missing a value (or you forgot a : somewhere)),
         $file,
         $line
      );

      # We set the value to prevent further errors
      $tag->value(q{});
   }

   # If there is a ! in front of a PRExxx tag, we remove it
   my $negate_pre = $tag =~ s/^!(pre)/$1/i ? 1 : 0;

   # [ 1387361 ] No KIT STARTPACK entry for \"KIT:xxx\"
   # STARTPACK lines in Kit files weren't getting added to $valid_entities. If
   # the verify flag is set and they aren't added to valid_entities, each Kit
   # will cause a spurious error. I've added them to valid entities to prevent
   # that.
   if ($tag eq 'STARTPACK') {
      LstTidy::Validate::setEntityValid('KIT STARTPACK', "KIT:$value");
      LstTidy::Validate::setEntityValid('KIT STARTPACK', "$value");
   }

   if (LstTidy::Options::isConversionActive('ALL:PRESPELLTYPE Syntax') && $tag eq 'PRESPELLTYPE') {
      $value = LstTidy::Convert::convertPreSpellType($value, $linetype, $file, $line);
   }

        # Continuing the fix - fix it anywhere. This is meant to address PRE tags
        # that are on the end of other tags or in PREMULTS.
        # I'll leave out the pipe-delimited error here, since it's more likely
        # to end up with confusion when the tag isn't standalone.
        elsif (LstTidy::Options::isConversionActive('ALL:PRESPELLTYPE Syntax')
                && $tag_text =~ /PRESPELLTYPE:([^\d]+),(\d+),(\d+)/)
        {
                $value =~ s/PRESPELLTYPE:([^\d,]+),(\d+),(\d+)/PRESPELLTYPE:$2,$1=$3/g;
                                $logger->notice(
                                        qq{Invalid embedded PRESPELLTYPE tag "$tag_text" found and converted $linetype.},
                                        $file,
                                        $line
                                );
        }

        # Special cases like ADD:... and BONUS:...
        if ( $tag eq 'ADD' ) {
                my ( $type, $addtag, $therest, $add_count )
                = parse_ADD_tag( $tag_text );
                #       Return code     0 = no valid ADD tag found,
                #                       1 = old format token ADD tag found,
                #                       2 = old format adlib ADD tag found.
                #                       3 = 5.12 format ADD tag, using known token.
                #                       4 = 5.12 format ADD tag, not using token.

                if ($type) {
                # It's a ADD:token tag
                if ( $type == 1) {
                        $tag   = $addtag;
                        $value = "($therest)$add_count";
                }
                        if ((($type == 1) || ($type == 2)) && (LstTidy::Options::isConversionActive('ALL:ADD Syntax Fix')))
                        {
                                $tag = "ADD:";
                                $addtag =~ s/ADD://;
                                $value = "$addtag|$add_count|$therest";
                        }
                }
                else {
                        unless ( index( $tag_text, '#' ) == 0 ) {
                                $logger->notice(
                                        qq{Invalid ADD tag "$tag_text" found in $linetype.},
                                        $file,
                                        $line
                                );
                                LstTidy::Report::incCountInvalidTags($linetype, $addtag); 
                                $no_more_error = 1;
                        }
                }
        }

        if ( $tag eq 'QUALIFY' ) {
                my ($qualify_type) = ($value =~ /^([^=:|]+)/ );
                if ($qualify_type && exists $token_QUALIFY_tag{$qualify_type} ) {
                        $tag .= ':' . $qualify_type;
                        $value =~ s/^$qualify_type(.*)/$1/;
                }
                elsif ($qualify_type) {
                        # No valid Qualify type found
                        LstTidy::Report::incCountInvalidTags($linetype, "$tag:$qualify_type"); 
                        $logger->notice(
                                qq{Invalid QUALIFY:$qualify_type tag "$tag_text" found in $linetype.},
                                $file,
                                $line
                        );
                        $no_more_error = 1;
                }
                else {
                        LstTidy::Report::incCountInvalidTags($linetype, "QUALIFY"); 
                        $logger->notice(
                                qq{Invalid QUALIFY tag "$tag_text" found in $linetype},
                                $file,
                                $line
                        );
                        $no_more_error = 1;
                }
        }

        if ( $tag eq 'BONUS' ) {
                my ($bonus_type) = ( $value =~ /^([^=:|]+)/ );

                if ( $bonus_type && exists $token_BONUS_tag{$bonus_type} ) {

                        # Is it valid for the curent file type?
                        $tag .= ':' . $bonus_type;
                        $value =~ s/^$bonus_type(.*)/$1/;
                }
                elsif ($bonus_type) {

                        # No valid bonus type was found
                        LstTidy::Report::incCountInvalidTags($linetype, "$tag:$bonus_type"); 
                        $logger->notice(
                                qq{Invalid BONUS:$bonus_type tag "$tag_text" found in $linetype.},
                                $file,
                                $line
                        );
                        $no_more_error = 1;
                }
                else {
                        LstTidy::Report::incCountInvalidTags($linetype, "BONUS"); 
                        $logger->notice(
                                qq{Invalid BONUS tag "$tag_text" found in $linetype},
                                $file,
                                $line
                        );
                        $no_more_error = 1;
                }
        }

        if ( $tag eq 'PROFICIENCY' ) {
                my ($prof_type) = ( $value =~ /^([^=:|]+)/ );

                if ( $prof_type && exists $token_PROFICIENCY_tag{$prof_type} ) {

                        # Is it valid for the curent file type?
                        $tag .= ':' . $prof_type;
                        $value =~ s/^$prof_type(.*)/$1/;
                }
                elsif ($prof_type) {

                        # No valid bonus type was found
                        LstTidy::Report::incCountInvalidTags($linetype, "$tag:$prof_type"); 
                        $logger->notice(
                                qq{Invalid PROFICIENCY:$prof_type tag "$tag_text" found in $linetype.},
                                $file,
                                $line
                        );
                        $no_more_error = 1;
                }
                else {
                        LstTidy::Report::incCountInvalidTags($linetype, "PROFICIENCY"); 
                        $logger->notice(
                                qq{Invalid PROFICIENCY tag "$tag_text" found in $linetype},
                                $file,
                                $line
                        );
                        $no_more_error = 1;
                }
        }


        # [ 832171 ] AUTO:* needs to be separate tags
        if ( $tag eq 'AUTO' ) {
                my $found_auto_type;
                AUTO_TYPE:
                for my $auto_type ( sort { length($b) <=> length($a) || $a cmp $b } @token_AUTO_tag ) {
                        if ( $value =~ s/^$auto_type// ) {
                                # We found what we were looking for
                                $found_auto_type = $auto_type;
                                last AUTO_TYPE;
                        }
                }

                if ($found_auto_type) {
                        $tag .= ':' . $found_auto_type;
                }
                else {

                        # No valid auto type was found
                        if ( $value =~ /^([^=:|]+)/ ) {
                           LstTidy::Report::incCountInvalidTags($linetype, "$tag:$1"); 
                                $logger->notice(
                                        qq{Invalid $tag:$1 tag "$tag_text" found in $linetype.},
                                        $file,
                                        $line
                                );
                        }
                        else {
                                LstTidy::Report::incCountInvalidTags($linetype, "AUTO"); 
                                $logger->notice(
                                        qq{Invalid AUTO tag "$tag_text" found in $linetype},
                                        $file,
                                        $line
                                );
                        }
                        $no_more_error = 1;

                }
        }

        # [ 813504 ] SPELLLEVEL:DOMAIN in domains.lst
        # SPELLLEVEL is now a multiple level tag like ADD and BONUS

        if ( $tag eq 'SPELLLEVEL' ) {
                if ( $value =~ s/^CLASS(?=\|)// ) {
                        # It's a SPELLLEVEL:CLASS tag
                        $tag = "SPELLLEVEL:CLASS";
                }
                elsif ( $value =~ s/^DOMAIN(?=\|)// ) {
                        # It's a SPELLLEVEL:DOMAIN tag
                        $tag = "SPELLLEVEL:DOMAIN";
                }
                else {
                        # No valid SPELLLEVEL subtag was found
                        if ( $value =~ /^([^=:|]+)/ ) {
                                LstTidy::Report::incCountInvalidTags($linetype, "$tag:$1"); 
                                $logger->notice(
                                        qq{Invalid SPELLLEVEL:$1 tag "$tag_text" found in $linetype.},
                                        $file,
                                        $line
                                );
                        }
                        else {
                                LstTidy::Report::incCountInvalidTags($linetype, "SPELLLEVEL"); 
                                $logger->notice(
                                        qq{Invalid SPELLLEVEL tag "$tag_text" found in $linetype},
                                        $file,
                                        $line
                                );
                        }
                        $no_more_error = 1;
                }
        }

        # [ 2544134 ] New Token - SPELLKNOWN

        if ( $tag eq 'SPELLKNOWN' ) {
                if ( $value =~ s/^CLASS(?=\|)// ) {
                        # It's a SPELLKNOWN:CLASS tag
                        $tag = "SPELLKNOWN:CLASS";
                }
                elsif ( $value =~ s/^DOMAIN(?=\|)// ) {
                        # It's a SPELLKNOWN:DOMAIN tag
                        $tag = "SPELLKNOWN:DOMAIN";
                }
                else {
                        # No valid SPELLKNOWN subtag was found
                        if ( $value =~ /^([^=:|]+)/ ) {
                                LstTidy::Report::incCountInvalidTags($linetype, "$tag:$1"); 
                                $logger->notice(
                                        qq{Invalid SPELLKNOWN:$1 tag "$tag_text" found in $linetype.},
                                        $file,
                                        $line
                                );
                        }
                        else {
                                LstTidy::Report::incCountInvalidTags($linetype, "SPELLKNOWN"); 
                                $logger->notice(
                                        qq{Invalid SPELLKNOWN tag "$tag_text" found in $linetype},
                                        $file,
                                        $line
                                );
                        }
                        $no_more_error = 1;
                }
        }

        # All the .CLEAR must be separated tags to help with the
        # tag ordering. That is, we need to make sure the .CLEAR
        # is ordered before the normal tag.
        # If the .CLEAR version of the tag doesn't exists, we do not
        # change the tag name but we give a warning.
        if ( defined $value && $value =~ /^.CLEAR/i ) {
                if ( LstTidy::Reformat::isValidTag($linetype, "$tag:.CLEARALL")) {
                        # Nothing to see here. Move on.
                } elsif ( ! LstTidy::Reformat::isValidTag($linetype, "$tag:.CLEAR")) {
                        $logger->notice(
                                qq{The tag "$tag:.CLEAR" from "$tag_text" is not in the $linetype tag list\n},
                                $file,
                                $line
                        );
                        LstTidy::Report::incCountInvalidTags($linetype, "$tag:.CLEAR"); 
                        $no_more_error = 1;
                }
                else {
                        $value =~ s/^.CLEAR//i;
                        $tag .= ':.CLEAR';
                }
        }

        # Verify if the tag is valid for the line type
        my $real_tag = ( $negate_pre ? "!" : "" ) . $tag;



        if ( !$no_more_error && !  LstTidy::Reformat::isValidTag($linetype, $tag) && index( $tag_text, '#' ) != 0 ) {
                my $do_warn = 1;
                if ($tag_text =~ /^ADD:([^\(\|]+)[\|\(]+/) {
                        my $tag_text = ($1);
                        if (LstTidy::Reformat::isValidTag($linetype, "ADD:$tag_text")) {
                                $do_warn = 0;
                        }
                }
                if ($do_warn) {
                        $logger->notice(
                                qq{The tag "$tag" from "$tag_text" is not in the $linetype tag list\n},
                                $file,
                                $line
                                );
                        LstTidy::Report::incCountInvalidTags($linetype, $real_tag); 
                }
        }


        elsif (LstTidy::Reformat::isValidTag($linetype, $tag)) {

           # Statistic gathering
           LstTidy::Report::incCountValidTags($linetype, $real_tag);
        }

        # Check and reformat the values for the tags with
        # only a limited number of values.

        if ( exists $tag_fix_value{$tag} ) {

           # All the limited value are uppercase except the alignment value 'Deity'
           my $newvalue = uc($value);
           my $is_valid = 1;

           # Special treament for the ALIGN tag
           if ( $tag eq 'ALIGN' || $tag eq 'PREALIGN' ) {
              # It is possible for the ALIGN and PREALIGN tags to have more then
              # one value

              # ALIGN use | for separator, PREALIGN use ,
              my $slip_patern = $tag eq 'PREALIGN' ? qr{[,]}xms : qr{[|]}xms;

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
                 if (!exists $tag_fix_value{$tag}{$align}) {
                    $logger->notice(
                       qq{Invalid value "$align" for tag "$real_tag"},
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
                if ( !exists $tag_fix_value{$tag}{$newvalue} ) {
                        $logger->notice(
                                qq{Invalid value "$value" for tag "$real_tag"},
                                $file,
                                $line
                        );
                        $is_valid = 0;
                }
                }



                # Was the tag changed ?
                if ( $is_valid && $value ne $newvalue && !( $tag eq 'ALIGN' || $tag eq 'PREALIGN' )) {
                $logger->warning(
                        qq{Replaced "$real_tag:$value" by "$real_tag:$newvalue"},
                        $file,
                        $line
                );
                $value = $newvalue;
                }
        }

        ############################################################
        ######################## Conversion ########################
        # We manipulate the tag here
        additionnal_tag_parsing( $real_tag, $value, $linetype, $file, $line );

        ############################################################
        # We call the validating function if needed
        if (getOption('xcheck')) {
           validate_tag($real_tag, $value, $linetype, $file, $line)
        };

        # If there is already a :  in the tag name, no need to add one more
        my $need_sep = index( $real_tag, ':' ) == -1 ? q{:} : q{};

        if ($value eq q{}) {
           $logger->debug(qq{parse_tag: $tag_text}, $file, $line)
        };

        # We change the tag_text value from the caller
        # This is very ugly but it gets th job done
        $_[0] = $real_tag;
        $_[0] .= $need_sep . $value if defined $value;

        # Return the tag
        wantarray ? ( $real_tag, $value ) : $real_tag;

}
