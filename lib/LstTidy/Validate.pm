package LstTidy::Validate;

use strict;
use warnings;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Parse;

# The PRExxx tags. They are used in many of the line types.
# From now on, they are defined in only one place and every
# line type will get the same sort order.
my @PRE_Tags = (
        'PRE:.CLEAR',
        'PREABILITY:*',
        '!PREABILITY',
        'PREAGESET',
        '!PREAGESET',
        'PREALIGN:*',
        '!PREALIGN:*',
        'PREARMORPROF:*',
        '!PREARMORPROF',
        'PREARMORTYPE',
        '!PREARMORTYPE',
        'PREATT',
        '!PREATT',
        'PREBASESIZEEQ',
        '!PREBASESIZEEQ',
        'PREBASESIZEGT',
        '!PREBASESIZEGT',
        'PREBASESIZEGTEQ',
        '!PREBASESIZEGTEQ',
        'PREBASESIZELT',
        '!PREBASESIZELT',
        'PREBASESIZELTEQ',
        '!PREBASESIZELTEQ',
        'PREBASESIZENEQ',
        'PREBIRTHPLACE',
        '!PREBIRTHPLACE',
        'PRECAMPAIGN',
        '!PRECAMPAIGN',
        'PRECHECK',
        '!PRECHECK',
        'PRECHECKBASE',
        '!PRECHECKBASE',
        'PRECITY',
        '!PRECITY',
        'PRECHARACTERTYPE',
        '!PRECHARACTERTYPE',
        'PRECLASS',
        '!PRECLASS',
        'PRECLASSLEVELMAX',
        '!PRECLASSLEVELMAX',
        'PRECSKILL',
        '!PRECSKILL',
        'PREDEITY',
        '!PREDEITY',
        'PREDEITYALIGN',
        '!PREDEITYALIGN',
        'PREDEITYDOMAIN',
        '!PREDEITYDOMAIN',
        'PREDOMAIN',
        '!PREDOMAIN',
        'PREDR',
        '!PREDR',
        'PREEQUIP',
        '!PREEQUIP',
        'PREEQUIPBOTH',
        '!PREEQUIPBOTH',
        'PREEQUIPPRIMARY',
        '!PREEQUIPPRIMARY',
        'PREEQUIPSECONDARY',
        '!PREEQUIPSECONDARY',
        'PREEQUIPTWOWEAPON',
        '!PREEQUIPTWOWEAPON',
        'PREFEAT:*',
        '!PREFEAT',
        'PREFACT:*',
        '!PREFACT',
        'PREGENDER',
        '!PREGENDER',
        'PREHANDSEQ',
        '!PREHANDSEQ',
        'PREHANDSGT',
        '!PREHANDSGT',
        'PREHANDSGTEQ',
        '!PREHANDSGTEQ',
        'PREHANDSLT',
        '!PREHANDSLT',
        'PREHANDSLTEQ',
        '!PREHANDSLTEQ',
        'PREHANDSNEQ',
        'PREHD',
        '!PREHD',
        'PREHP',
        '!PREHP',
        'PREITEM',
        '!PREITEM',
        'PRELANG',
        '!PRELANG',
        'PRELEGSEQ',
        '!PRELEGSEQ',
        'PRELEGSGT',
        '!PRELEGSGT',
        'PRELEGSGTEQ',
        '!PRELEGSGTEQ',
        'PRELEGSLT',
        '!PRELEGSLT',
        'PRELEGSLTEQ',
        '!PRELEGSLTEQ',
        'PRELEGSNEQ',
        'PRELEVEL',
        '!PRELEVEL',
        'PRELEVELMAX',
        '!PRELEVELMAX',
        'PREKIT',
        '!PREKIT',
        'PREMOVE',
        '!PREMOVE',
        'PREMULT:*',
        '!PREMULT:*',
        'PREPCLEVEL',
        '!PREPCLEVEL',
        'PREPROFWITHARMOR',
        '!PREPROFWITHARMOR',
        'PREPROFWITHSHIELD',
        '!PREPROFWITHSHIELD',
        'PRERACE:*',
        '!PRERACE:*',
        'PREREACH',
        '!PREREACH',
        'PREREACHEQ',
        '!PREREACHEQ',
        'PREREACHGT',
        '!PREREACHGT',
        'PREREACHGTEQ',
        '!PREREACHGTEQ',
        'PREREACHLT',
        '!PREREACHLT',
        'PREREACHLTEQ',
        '!PREREACHLTEQ',
        'PREREACHNEQ',
        'PREREGION',
        '!PREREGION',
        'PRERULE',
        '!PRERULE',
        'PRESA',
        '!PRESA',
        'PRESITUATION',
        '!PRESITUATION',
        'PRESHIELDPROF',
        '!PRESHIELDPROF',
        'PRESIZEEQ',
        '!PRESIZEEQ',
        'PRESIZEGT',
        '!PRESIZEGT',
        'PRESIZEGTEQ',
        '!PRESIZEGTEQ',
        'PRESIZELT',
        '!PRESIZELT',
        'PRESIZELTEQ',
        '!PRESIZELTEQ',
        'PRESIZENEQ',
        'PRESKILL:*',
        '!PRESKILL',
        'PRESKILLMULT',
        '!PRESKILLMULT',
        'PRESKILLTOT',
        '!PRESKILLTOT',
        'PRESPELL:*',
        '!PRESPELL',
        'PRESPELLBOOK',
        '!PRESPELLBOOK',
        'PRESPELLCAST:*',
        '!PRESPELLCAST:*',
        'PRESPELLDESCRIPTOR',
        'PRESPELLSCHOOL:*',
        '!PRESPELLSCHOOL',
        'PRESPELLSCHOOLSUB',
        '!PRESPELLSCHOOLSUB',
        'PRESPELLTYPE:*',
        '!PRESPELLTYPE',
        'PRESREQ',
        '!PRESREQ',
        'PRESRGT',
        '!PRESRGT',
        'PRESRGTEQ',
        '!PRESRGTEQ',
        'PRESRLT',
        '!PRESRLT',
        'PRESRLTEQ',
        '!PRESRLTEQ',
        'PRESRNEQ',
        'PRESTAT:*',
        '!PRESTAT',
        'PRESTATEQ',
        '!PRESTATEQ',
        'PRESTATGT',
        '!PRESTATGT',
        'PRESTATGTEQ',
        '!PRESTATGTEQ',
        'PRESTATLT',
        '!PRESTATLT',
        'PRESTATLTEQ',
        '!PRESTATLTEQ',
        'PRESTATNEQ',
        'PRESUBCLASS',
        '!PRESUBCLASS',
        'PRETEMPLATE:*',
        '!PRETEMPLATE:*',
        'PRETEXT',
        '!PRETEXT',
        'PRETYPE:*',
        '!PRETYPE:*',
        'PRETOTALAB:*',
        '!PRETOTALAB:*',
        'PREUATT',
        '!PREUATT',
        'PREVAREQ:*',
        '!PREVAREQ:*',
        'PREVARGT:*',
        '!PREVARGT:*',
        'PREVARGTEQ:*',
        '!PREVARGTEQ:*',
        'PREVARLT:*',
        '!PREVARLT:*',
        'PREVARLTEQ:*',
        '!PREVARLTEQ:*',
        'PREVARNEQ:*',
        'PREVISION',
        '!PREVISION',
        'PREWEAPONPROF:*',
        '!PREWEAPONPROF:*',
        'PREWIELD',
        '!PREWIELD',

        # Removed tags
        #       'PREVAR',
);

# Hash used by validate_pre_tag to verify if a PRExxx tag exists
my %PRE_Tags = (
   'PREAPPLY'          => 1,   # Only valid when embeded - THIS IS DEPRECATED
   'PREDEFAULTMONSTER' => 1,   # Only valid when embeded
);

for my $pre_tag (@PRE_Tags) {
        # We need a copy since we don't want to modify the original
        my $pre_tag_name = $pre_tag;

        # We strip the :* at the end to get the real name for the lookup table
        $pre_tag_name =~ s/ [:][*] \z//xms;

        $PRE_Tags{$pre_tag_name} = 1;
}


# Will hold the portions of a race that have been matched with wildcards.
# For example, if Elf% has been matched (given no default Elf races).
my %race_partial_match; 

# Will hold the entries that may be refered to by other tags Format
# $valid_entities{$entitytype}{$entityname} We initialise the hash with global
# system values that are valid but never defined in the .lst files.
my %valid_entities;     

# Will hold the valid types for the TYPE. or TYPE= found in different tags.
# Format valid_types{$entitytype}{$typename}
my %valid_types;

# Will hold the valid categories for CATEGORY= found in abilities.
# Format valid_categories{$entitytype}{$categoryname}
my %valid_categories;   

=head2 getValidTypes

   Return a reference to the has of valid types for cross checking.

   Format valid_types{$entitytype}{$typename}

=cut

sub getValidTypes {
   return \%valid_types;
}

=head2 getValidCategories

   Return a reference to the hash of valid categories for cross checking.

   Format valid_categories{$entitytype}{$categoryname}

=cut

sub getValidCategories {
   return \%valid_categories;
}



=head2 isEntityValid

   Returns true if the entity is valid.

=cut

sub isEntityValid {
   my ($entitytype, $entityname) = @_;

   return exists $valid_entities{$entitytype}{$entityname};
}

=head2 setEntityValid

   Increments the number of times entity has been seen, and makes the exists
   test true for this entity.

=cut

sub setEntityValid {
   my ($entitytype, $entityname) = @_;

   $valid_entities{$entitytype}{$entityname}++;
}

=head2 splitAndAddToValidEntities

   ad-hod/special list of thingy It adds to the valid entities instead of the
   valid sub-entities.  We do this when we find a CHOOSE but we do not know what
   it is for.

=cut

sub splitAndAddToValidEntities {
   my ($entitytype, $ability, $value) = @_;

   for my $abil ( split '\|', $value ) {
      $valid_entities{'ABILITY'}{"$ability($abil)"}  = $value;
      $valid_entities{'ABILITY'}{"$ability ($abil)"} = $value;
   }
}

=head2 searchRace

   Searches the Race entries of valid entities looking for a match for
   the given race.

=cut

sub searchRace {
   my ($race_wild) = @_;

   for my $toCheck (keys %{$valid_entities{'RACE'}} ) {
      if ($toCheck =~  m/^\Q$race_wild/) {
         return 1;
      }
   }
   return 0;
}


=head2 warnDeprecate

   Generate a warning message about a deprecated tag.
   
   Parameters: $bad_tag         Tag that has been deprecated
               $files_for_error File name when the error is found
               $line_for_error  Line number where the error is found
               $enclosing_tag   (Optionnal) tag into which the deprecated tag is included

=cut

sub warnDeprecate {

   my ($bad_tag, $file_for_error, $line_for_error, $enclosing_tag) = (@_, "");

   my $message = qq{Deprecated syntax: "$bad_tag"};

   if($enclosing_tag) {
      $message .= qq{ found in "$enclosing_tag"};
   }

   $log->info( $message, $file_for_error, $line_for_error );

}







=head2 checkFirstValue 

   Check the Values in the PRE tag to ensure it starts with a number.

=cut

sub checkFirstValue {

   # We get the list of values
   my @values = split ',', $_[0];

   # first entry is a number
   my $valid = $values[0] =~ / \A \d+ \z /xms;

   # get rid of the number
   shift @values if $valid;

   return $valid, @values; 
}

=head2 processGenericPRE

   Process a PRE tag

   Check for deprecated syntax and queue up for cross check.

=cut

sub processGenericPRE {

   my ($preType, $tag, $tagValue, $enclosingTag, $file, $line) = @_;

   my ($valid, @values) = checkFirstValue($tagValue);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate("$tag:$tagValue", $file, $line, $enclosingTag);
   }

   LstTidy::Report::registerXCheck($preType, $tag, $file, $line, @values);
}

=head2 processPRECHECK

   Check the PRECHECK familiy of PRE tags for validity.

   Ensures they start with a number.

   Ensures that the checks are valid.

=cut

sub processPRECHECK {

   my ($tag, $tagValue, $enclosingTag, $file, $line) = @_;

   # PRECHECK:<number>,<check equal value list>
   # PRECHECKBASE:<number>,<check equal value list>
   # <check equal value list> := <check name> "=" <number>
   my ($valid, @values) = checkFirstValue(i$tagValue);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate("$tag:$tagValue", $file, $line, $enclosingTag);
   }
  
   # Get the logger once outside the loop 
   my $logger = LstTidy::LogFactory::getLogger();

   for my $item ( @values ) {

      # Extract the check name
      if ( my ($check_name, $value) = ( $item =~ / \A ( \w+ ) = ( \d+ ) \z /xms ) ) {

         # If we don't recognise it.
         if ( ! LstTidy::Parse::isValidCheck($check_name) ) {
            $logger->notice(
               qq{Invalid save check name "$check_name" found in "$tag:$tagValue"},
               $file,
               $line
            );
         }
      } else {
         $logger->notice(
            qq{$tag syntax error in "$item" found in "$tag:$tagValue"},
            $file,
            $line
         );
      }
   }
}

=head2 processPRECSKILL

   Process the PRECSKILL tags

   Ensure they start with a number and if so, queue for cross checking.

=cut


=head2 processPREDIETY

   Process the PREDIETY tags

   Queue up for Cross check.

=cut

sub processPREDIETY {

   my ( $tag, $tagValue, $file, $line) = @_;

   #PREDEITY:Y
   #PREDEITY:YES
   #PREDEITY:N
   #PREDEITY:NO
   #PREDEITY:1,<deity name>,<deity name>,etc.
   
   if ( $tagValue !~ / \A (?: Y(?:ES)? | N[O]? ) \z /xms ) {
      #We ignore the single yes or no
      LstTidy::Report::registerXCheck('DEITY', $tag, $file, $line, (split /[,]/, $tagValue)[1,-1],);
   }
};

      
=head2 processPRELANG

   Process the PRELANG tags

   Check for deprecated syntax and quque up for cross check.

=cut

sub processPRELANG {

   my ($tag, $tagValue, $enclosingTag, $file, $line) = @_;

   # PRELANG:number,language,language,TYPE=type
   my ($valid, @values) = checkFirstValue(i$tagValue);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate("$tag:$tagValue", $file, $line, $enclosingTag);
   }

   LstTidy::Report::registerXCheck('LANGUAGE', $tag, $file, $line, grep { $_ ne 'ANY' } @values);
}

=head2 processPREMOVE

   Process the PREMOVE tags

   Check for deprecated syntax and quque up for cross check.

=cut

sub processPREMOVE {

   my ($tag, $tagValue, $enclosingTag, $file, $line) = @_;

   # PREMOVE:[<number>,]<move>=<number>,<move>=<number>,...
   my ($valid, @values) = checkFirstValue(i$tagValue);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate("$tag:$tagValue", $file, $line, $enclosingTag);
   }

   for my $move (@values) {

      # Verify that the =<number> is there
      if ( $move =~ /^([^=]*)=([^=]*)$/ ) {

         LstTidy::Report::registerXCheck('MOVE Type', $tag, $file, $line, $1);

         # The value should be a number
         my $value = $2;

         if ($value !~ /^\d+$/ ) {
            my $message = qq{Not a number after the = for "$move" in "$tag:$tagValue"};
            $message .= qq{ found in "$enclosingTag"} if $enclosingTag;
   
            LstTidy::LogFactory::getLogger()->notice($message, $file, $line);
         }

      } else {

         my $message = qq{Invalid "$move" in "$tag:$tagValue"};
         $message .= qq{ found in "$enclosingTag"} if $enclosingTag;
   
         LstTidy::LogFactory::getLogger()->notice($message, $file, $line);

      }
   }
}

=head2 processPREMULT

   split and check the PREMULT tags

   Each PREMULT tag has two or more embedded PRE tags, which are individually
   checked using validatePreTag.

=cut

sub processPREMULT {

   my ($tag, $tagValue, $enclosingTag, $lineType, $file, $line) = @_;

   my $working_value = $tagValue;
   my $inside;

   # We add only one level of PREMULT to the error message.
   my $emb_tag;
   if ($enclosingTag) {

      $emb_tag = $enclosingTag;
      $emb_tag .= ':PREMULT' unless $emb_tag =~ /PREMULT$/;

   } else {

      $emb_tag .= 'PREMULT';
   }

   FIND_BRACE:
   while ($working_value) {

      ( $inside, $working_value ) = Text::Balanced::extract_bracketed( $working_value, '[]', qr{[^[]*} );

      last FIND_BRACE if !$inside;

      # We extract what we need
      my ( $XXXPREXXX, $value ) = ( $inside =~ /^\[(!?PRE[A-Z]+):(.*)\]$/ );

      if ($XXXPREXXX) {

         validatePreTag($XXXPREXXX, $value, $emb_tag, $lineType, $file, $line);
      
      } else {

         # No PRExxx tag found inside the PREMULT
         LstTidy::LogFactory::getLogger()->warning(
            qq{No valid PRExxx tag found in "$inside" inside "PREMULT:$tagValue"},
            $file,
            $line
         );
      }
   }
}

=head2 processPRERACE


=cut

sub processPRERACE {

   my ($tag, $tagValue, $enclosingTag, $file, $line) = @_;

   # We get the list of races
   my ($valid, @values) = checkFirstValue(i$tagValue);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate("$tag:$tagValue", $file, $line, $enclosingTag);
   }

   my ( @races, @races_wild );

   for my $race (@values) {

      if ( $race =~ / (.*?) [%] (.*?) /xms ) {
         # Special case for PRERACE:xxx%
         my $race_wild  = $1;
         my $after_wild = $2;

         push @races_wild, $race_wild;

         if ( $after_wild ne q{} ) {

            LstTidy::LogFactory::getLogger()->notice(
               qq{% used in wild card context should end the race name in "$race"},
               $file,
               $line
            );

         } else {

            # Don't bother warning if it matches everything.
            # For now, we warn and do nothing else.
            if ($race_wild eq '') {

               ## Matches everything, no reason to warn.

            } elsif ($valid_entities{'RACE'}{$race_wild}) {

               ## Matches an existing race, no reason to warn.

            } elsif ($race_partial_match{$race_wild}) {

               ## Partial match already confirmed, no need to confirm.
               #
            } else {

               my $found = searchRace($race_wild) ;

               if ($found) {
                  $race_partial_match{$race_wild} = 1;
               } else {

                  LstTidy::LogFactory::getLogger()->info(
                     qq{Not able to validate "$race" in "PRERACE:$tagValue." This warning is order dependent.} . 
                     q{ If the race is defined in a later file, this warning may not be accurate.},
                     $file,
                     $line
                  )
               }
            }
         }
      } else {
         push @races, $race;
      }
   }

   LstTidy::Report::registerXCheck('RACE', $tag, $file, $line, @races);
}


=head2 processPRESPELL

   Process the PRESPELL tags

   Check for deprecated syntax and quque up for cross check.

=cut

sub processPRESPELL {

   my ($tag, $tagValue, $enclosingTag, $file, $line) = @_;

   # We get the list of skills and skill types
   my ($valid, @values) = checkFirstValue(i$tagValue);

   # The PREtag doesn't begin with a number
   if ( not $valid ) {
      warnDeprecate("$tag:$tagValue", $file, $line, $enclosingTag);
   }

   LstTidy::Report::registerXCheck('SPELL', "$tag:@@", $file, $line, @values);
}

=head2 processPREVAR

=cut

sub processPREVAR {

   my ($tag, $tagValue, $enclosingTag, $file, $line) = @_;

   my ( $var_name, @formulas ) = split ',', $tagValue;

   LstTidy::Report::registerXCheck('DEFINE Variable', qq(@@" in "$tag:$tagValue), $file, $line, $var_name,);

   for my $formula (@formulas) {
      my @values = LstTidy::Parse::parseJep( $formula, "$tag:$tagValue", $file, $line);
      LstTidy::Report::registerXCheck('DEFINE Variable', qq(@@" in "$tag:$tagValue), $file, $line, @values);
   }
}

=head2 validatePreTag

   Validate the PRExxx tags. This function is reentrant and can be called
   recursivly.

   $tag,             # Name of the tag (before the :)
   $tagValue,        # Value of the tag (after the :)
   $enclosingTag,    # When the PRExxx tag is used in another tag
   $lineType,        # Type for the current file
   $file,            # Name of the current file
   $line             # Number of the current line

   preforms checks that pre tags are valid. 

=cut

sub validatePreTag {
   my ( $tag, $tagValue, $enclosingTag, $lineType, $file, $line) = @_;

   if ( !length($tagValue) && $tag ne "PRE:.CLEAR" ) {
      missingValue();
      return;
   }

   LstTidy::LogFactory::getLogger()->debug( 
      qq{validatePreTag: $tag; $tagValue; $enclosingTag; $lineType;},
      $file,
      $line
   );

   my $is_neg = 1 if $tag =~ s/^!(.*)/$1/;
   my $comp_op;

   # Special treatment for tags ending in MULT because of PREMULT and
   # PRESKILLMULT
   if ($tag !~ /MULT$/) {
      ($comp_op) = ( $tag =~ s/(.*)(EQ|GT|GTEQ|LT|LTEQ|NEQ)$/$1/ )[1];
   }

   if ( $tag eq 'PRECLASS' || $tag eq 'PRECLASSLEVELMAX' ) {

      processGenericPRE('CLASS', $tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PRECHECK' || $tag eq 'PRECHECKBASE') {

      processPRECHECK ( $tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PRECSKILL' ) {

      processGenericPRE('SKILL', $tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PREDEITY' ) {

      processPREDIETY($tag, $tagValue, $file, $line);

   } elsif ( $tag eq 'PREDEITYDOMAIN' || $tag eq 'PREDOMAIN' ) {

      processGenericPRE('DOMAIN', $tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PREFEAT' ) {

      processGenericPRE('FEAT', $tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PREABILITY' ) {

      processGenericPRE('ABILITY', $tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PREITEM' ) {

      processGenericPRE('EQUIPMENT', $tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PRELANG' ) {
      
      processPRELANG($tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PREMOVE' ) {

      processPREMOVE($tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PREMULT' ) {

      # This tag is the reason why validatePreTag exists
      # PREMULT:x,[PRExxx 1],[PRExxx 2]
      # We need for find all the [] and call validatePreTag with the content
   
      processPREMULT($tag, $tagValue, $enclosingTag, $lineType, $file, $line);

   } elsif ( $tag eq 'PRERACE' ) {

      processPRERACE($tag, $tagValue, $enclosingTag, $file, $line);

   }
   elsif ( $tag eq 'PRESKILL' ) {

      processGenericPRE('SKILL', $tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PRESPELL' ) {

      processPRESPELL($tag, $tagValue, $enclosingTag, $file, $line);

   } elsif ( $tag eq 'PREVAR' ) {

      # processGenericPRE('SPELL', $tag, $tagValue, $enclosingTag, $file, $line);
      processPREVAR($tag, $tagValue, $enclosingTag, $file, $line);

   }

   # No Check for Variable File #

   # Check for PRExxx that do not exist. We only check the
   # tags that are embeded since parse_tag already took care
   # of the PRExxx tags on the entry lines.
   elsif ( $enclosingTag && !exists $PRE_Tags{$tag} ) {
      
      LstTidy::LogFactory::getLogger()->notice(
         qq{Unknown PRExxx tag "$tag" found in "$enclosingTag"},
         $file,
         $line
      );
   }
}

1;
