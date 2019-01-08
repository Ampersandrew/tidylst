package TidyLst::Report;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw( 
   add_to_xcheck_tables
   closeExportListFileHandles
   doXCheck
   openExportListFileHandles
   printToExportList
   registerReferrer
   reportInvalid
   reportValid
   );

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Data qw(
   foundInvalidTags
   getCrossCheckData
   getHeaderMissingOnLineType
   getTagCount
   isValidCategory 
   isValidEntity 
   isValidSubEntity 
   isValidType
   validSubEntityExists
   );

use TidyLst::LogFactory qw(getLogger);
use TidyLst::Options qw(getOption isConversionActive);
# use TidyLst::Validate qw();

# predeclare this so we can call it without & or trailing () like a builtin
sub reportTagSort;

# populated in additional line processing used for a report
my %bonusAndPreTagReport = ();

# File handles for the Export Lists
our %filehandles;

# Will hold the tags that refer to other entries
# Format: push @{$referrer{$EntityType}{$entryname}}, [ $tags{$column}, $file_for_error, $line_for_error ]
my %referrer;

# Will hold the categories used by abilities to allow validation;
# [ 1671407 ] xcheck PREABILITY tag
my %referrer_categories;

# Will hold the type used by some of the tags to allow validation.
# Format: push @{$referrer_types{$EntityType}{$typename}}, [ $tags{$column}, $file_for_error, $line_for_error ]
my %referrer_types;


# Variables names that must be skiped for the DEFINE variable section
# entry type.

my %Hardcoded_Variables = map { $_ => 1 } (
   # Real hardcoded variables
   'ACCHECK',
   'BAB',
   'BASESPELLSTAT',
   '%CHOICE',
   'CASTERLEVEL',
   'CL',
   'ENCUMBERANCE',
   'HD',
   '%LIST',
   'MOVEBASE',
   'SIZE',
   'TL',

   # Functions for the JEP parser
   'ceil',
   'floor',
   'if',
   'min',
   'max',
   'roll',
   'var',
   'mastervar',
   'APPLIEDAS',
);


=head2 addToBonusAndPreReport

=cut

sub addToBonusAndPreReport {

   my ($lineRef, $fileType, $tagType) = @_;

   for my $tag ( @{ $lineRef->{$tagType} } ) {
      $bonusAndPreTagReport{$fileType}{$tag} = 1;
   };
}
                                


=head2 closeExportListFileHandles

   Close the file handles used for the export list function.

=cut

sub closeExportListFileHandles {

   # Close all the files in reverse order that they were opened
   for my $line_type ( reverse sort keys %filehandles ) {
      close $filehandles{$line_type};
   }
}





=head2 openExportListFileHandles

   Open the file handles for exporting lists of valid objects found (e.g.
   Classes in CLASS files, Deitys in DEITY files, etc.) and write a header to
   each.

=cut

sub openExportListFileHandles {
                
   # The files should be opened in alpha order since they will
   # be closed in reverse alpha order.

   # Will hold the list of all classes found in CLASS filetypes
   open $filehandles{CLASS}, '>', 'class.csv';
   print { $filehandles{CLASS} } qq{"Class Name","Line","Filename"\n};

   # Will hold the list of all deities found in DEITY filetypes
   open $filehandles{DEITY}, '>', 'deity.csv';
   print { $filehandles{DEITY} } qq{"Deity Name","Line","Filename"\n};

   # Will hold the list of all domains found in DOMAIN filetypes
   open $filehandles{DOMAIN}, '>', 'domain.csv';
   print { $filehandles{DOMAIN} } qq{"Domain Name","Line","Filename"\n};

   # Will hold the list of all equipements found in EQUIPMENT filetypes
   open $filehandles{EQUIPMENT}, '>', 'equipment.csv';
   print { $filehandles{EQUIPMENT} } qq{"Equipment Name","Output Name","Line","Filename"\n};

   # Will hold the list of all equipmod entries found in EQUIPMOD filetypes
   open $filehandles{EQUIPMOD}, '>', 'equipmod.csv';
   print { $filehandles{EQUIPMOD} } qq{"Equipmod Name","Key","Type","Line","Filename"\n};

   # Will hold the list of all feats found in FEAT filetypes
   open $filehandles{FEAT}, '>', 'feat.csv';
   print { $filehandles{FEAT} } qq{"Feat Name","Line","Filename"\n};

   # Will hold the list of all kits found in KIT filetypes
   open $filehandles{KIT}, '>', 'kit.csv';
   print { $filehandles{KIT} } qq{"Kit Startpack Name","Line","Filename"\n};

   # Will hold the list of all language found in LANGUAGE linetypes
   open $filehandles{LANGUAGE}, '>', 'language.csv';
   print { $filehandles{LANGUAGE} } qq{"Language Name","Line","Filename"\n};

   # Will hold the list of all PCC files found
   open $filehandles{PCC}, '>', 'pcc.csv';
   print { $filehandles{PCC} } qq{"SOURCELONG","SOURCESHORT","GAMEMODE","Full Path"\n};

   # Will hold the list of all races and race types found in RACE filetypes
   open $filehandles{RACE}, '>', 'race.csv';
   print { $filehandles{RACE} } qq{"Race Name","Race Type","Race Subtype","Line","Filename"\n};

   # Will hold the list of all skills found in SKILL filetypes
   open $filehandles{SKILL}, '>', 'skill.csv';
   print { $filehandles{SKILL} } qq{"Skill Name","Line","Filename"\n};

   # Will hold the list of all spells found in SPELL filetypes
   open $filehandles{SPELL}, '>', 'spell.csv';
   print { $filehandles{SPELL} } qq{"Spell Name","Source Page","Line","Filename"\n};

   # Will hold the list of all kit Tables found in KIT filetypes
   open $filehandles{TABLE}, '>', 'kit-table.csv';
   print { $filehandles{TABLE} } qq{"Table Name","Line","Filename"\n};

   # Will hold the list of all templates found in TEMPLATE filetypes
   open $filehandles{TEMPLATE}, '>', 'template.csv';
   print { $filehandles{TEMPLATE} } qq{"Tempate Name","Line","Filename"\n};

   # Will hold the list of all variables found in DEFINE tags
   if ( getOption('xcheck') ) {
      open $filehandles{VARIABLE}, '>', 'variable.csv';
      print { $filehandles{VARIABLE} } qq{"Var Name","Line","Filename"\n};
   }

   # We need to list the tags that use Willpower
   if ( isConversionActive('ALL:Find Willpower') ) {
      open $filehandles{Willpower}, '>', 'willpower.csv';
      print { $filehandles{Willpower} } qq{"Tag","Line","Filename"\n};
   }
}

=head2 printToExportList

   C<TidyLst::Report::printToExportList('handle', @stuff)>

   Prints the strings in @stuff to the filehandle named 'handle'.

=cut

sub printToExportList {
   my ($handle, @data) = @_;
   print { $filehandles{$handle} } @data;
}

=head2 registerReferrer

   Register this data for later cross checking

=cut

sub registerReferrer {
   my ($linetype, $entity_name, $token, $file, $line) = @_;

   push @{ $referrer{$linetype}{$entity_name} }, [ $token, $file, $line ]
}

=head2 report

   Print a report for the number of invalid tags found.

=cut

sub report {

   my ($reportType) = @_;

   my %tagCount = %{getTagCount()};

   my $maxNumLength = 0;
   for my $tag ( sort reportTagSort keys %{ $tagCount{$reportType}{"Total"} } ) {
      if (length($tagCount{$reportType}{"Total"}{$tag}) >= $maxNumLength) {
         $maxNumLength = length($tagCount{$reportType}{"Total"}{$tag});
      }
   }
   $maxNumLength++;
   my $format = "% ${maxNumLength}d";

   my $log = getLogger();

   my $header = $reportType . ' Tags';

   $log->header(TidyLst::LogHeader::get($header));

   my $first = 1;
   LINE_TYPE:
   for my $lineType ( sort grep {$_ ne 'Total'} keys %{ $tagCount{$reportType} } ) {

      my $lineHead = $first ? "Line Type: $lineType\n" : "\nLine Type: $lineType\n";
      $log->report($lineHead);

      for my $tag ( sort reportTagSort keys %{ $tagCount{$reportType}{$lineType} } ) {

         my $line = "    $tag";
         $line .= ( " " x ( 26 - length($tag) ) );
         $line .= sprintf $format, $tagCount{$reportType}{$lineType}{$tag};
         $log->report($line);
      }

      $first = 0;
   }

   $log->report("\nTotal:\n");

   for my $tag ( sort reportTagSort keys %{ $tagCount{$reportType}{"Total"} } ) {

      my $line = "    $tag";
      $line .= ( " " x ( 26 - length($tag) ) );
      $line .= sprintf $format, $tagCount{$reportType}{"Total"}{$tag};
      $log->report($line);

   }
}


=head2 reportBonus

=cut

sub reportBonus {

   my $log = getLogger();

   $log->header(TidyLst::LogHeader::get('Bonus and PRE'));

   my $first = 1;
   LINE_TYPE:
   for my $lineType (sort keys %bonusAndPreTagReport) {

      my $lineHead = $first ? "Line Type: $lineType" : "\nLine Type: $lineType";
      $log->report($lineHead);

      for my $tag (sort keys %{$bonusAndPreTagReport{$lineType}}) {
         $log->report("  $tag");
      }
      $first = 0;
   }

   $log->report("================================================================");
}



=head2 reportTagSort

   A sort operation used on the list of tags when reporting.

   It's a normal ASCII sort except that leading ! are removed when found.  This
   means that PRExxx and !PRExxx are sorted together, with !PRExxx following
   PRExxx.

=cut

sub reportTagSort {
   my ( $left, $right ) = ( $a, $b );      # We need a copy in order to modify

   # Remove the !. $not_xxx contains 1 if there was a !, otherwise
   # it contains 0.
   my $not_left  = $left  =~ s{^!}{}xms;
   my $not_right = $right =~ s{^!}{}xms;

   $left cmp $right || $not_left <=> $not_right;
}





=head2 add_to_xcheck_tables
   
   This function adds entries that will need to cross-checked
   against existing entities.
   
   It also filters the global entries and other weirdness.
   
   Pamameter:  $entityType  Type of the entry that must be cheacked
   
               $tagName     Name of the tag for message display
                            If tag name contains @@, it will be replaced by the
                            entry text from the list for the message.
                            Otherwise, the format $tagName:$list_entry will be
                            used.
   
               $file        Name of the current file
               $line        Number of the current line
               @list        List of entries to be added
=cut


sub add_to_xcheck_tables {
   my ($entityType, $tagName, $file, $line, @list) = ( @_, "" );

   # If $file is not under getOption('inputpath'), we do not add
   # it to be validated. This happens when a -basepath parameter is used
   # with the script.
   my $inputpath =  getOption('inputpath');
   return if $file !~ / \A ${inputpath} /xmsi;

   # We remove the empty elements in the list
   @list = grep { defined $_ && $_ ne "" } @list;

   # If the list of entry is empty, we retrun immediately
   return if scalar @list == 0;

   # We set $tagName properly for the substitution
   $tagName .= ":@@" unless $tagName =~ /@@/;

   if ( $entityType eq 'CLASS' ) {
      for my $class (@list) {

         # Remove the =level if there is one
         $class =~ s/(.*)=\d+$/$1/;

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$class/;

         # Spellcaster is a special PCGEN keyword, not a real class
         push @{ $referrer{'CLASS'}{$class} }, [ $message_name, $file, $line ]
         if ( uc($class) ne "SPELLCASTER"
            && uc($class) ne "SPELLCASTER.ARCANE"
            && uc($class) ne "SPELLCASTER.DIVINE"
            && uc($class) ne "SPELLCASTER.PSIONIC" );
      }

   } elsif ( $entityType eq 'DEFINE Variable' ) {

      VARIABLE:
      for my $var (@list) {

         # We skip, the COUNT[] thingy must not be validated
         next VARIABLE if $var =~ /^COUNT\[/;

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$var/;

         push @{ $referrer{'DEFINE Variable'}{$var} }, [ $message_name, $file, $line ] unless $Hardcoded_Variables{$var};
      }

   } elsif ( $entityType eq 'DEITY' ) {

      for my $deity (@list) {
         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$deity/;

         push @{ $referrer{'DEITY'}{$deity} }, [ $message_name, $file, $line ];
      }

   } elsif ( $entityType eq 'DOMAIN' ) {

      for my $domain (@list) {

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$domain/;

         push @{ $referrer{'DOMAIN'}{$domain} }, [ $message_name, $file, $line ];
      }

   } elsif ( $entityType eq 'EQUIPMENT' ) {

      for my $equipment (@list) {

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$equipment/;

         if ( $equipment =~ /^TYPE=(.*)/ ) {

            push @{ $referrer_types{'EQUIPMENT'}{$1} }, [ $message_name, $file, $line ];

         } else {
         
            push @{ $referrer{'EQUIPMENT'}{$equipment} }, [ $message_name, $file, $line ];
        
         }
      }

   } elsif ( $entityType eq 'EQUIPMENT TYPE' ) {

      for my $type (@list) {

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$type/;

         push @{ $referrer_types{'EQUIPMENT'}{$type} }, [ $message_name, $file, $line ]; }

   } elsif ( $entityType eq 'EQUIPMOD Key' ) {

      for my $key (@list) {

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$key/;

         push @{ $referrer{'EQUIPMOD Key'}{$key} }, [ $message_name, $file, $line ];
      }

   } elsif ( $entityType eq 'FEAT' ) {

      # Note - ABILITY code is below. If you need to make changes here
      # to the FEAT code, please also review the ABILITY code to ensure
      # that your changes aren't needed there.
      FEAT:
      for my $feat (@list) {

         # We ignore CHECKMULT if used within a PREFEAT tag
         next FEAT if $feat eq 'CHECKMULT' && $tagName =~ /PREFEAT/;

         # We ignore LIST if used within an ADD:FEAT tag
         next FEAT if $feat eq 'LIST' && $tagName eq 'ADD:FEAT';

         # We stript the () if any
         if ( $feat =~ /(.*?[^ ]) ?\((.*)\)/ ) {

            # We check to see if the FEAT is a compond tag
            if ( isValidSubEntity('FEAT', $1) ) {
               my $original_feat = $feat;
               my $feat_to_check = $feat = $1;
               my $entity              = $2;
               my $sub_tagName  = $tagName;
               $sub_tagName =~ s/@@/$feat (@@)/;

               # Find the real entity type in case of FEAT=
               FEAT_ENTITY:
               while ( isValidSubEntity('FEAT', $feat_to_check) =~ /^FEAT=(.*)/ ) {
                  $feat_to_check = $1;
                  if ( !validSubEntityExists('FEAT', $feat_to_check) ) {
                     getLogger()->notice(
                        qq{Cannot find the sub-entity for "$original_feat"},
                        $file,
                        $line
                     );
                     $feat_to_check = "";
                     last FEAT_ENTITY;
                  }
               }

               add_to_xcheck_tables(
                  isValidSubEntity('FEAT', $feat_to_check),
                  $sub_tagName,
                  $file,
                  $line,
                  $entity
               ) if $feat_to_check && $entity ne 'Ad-Lib';
            }
         }

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$feat/;

         if ( $feat =~ /^TYPE[=.](.*)/ ) {

            push @{ $referrer_types{'FEAT'}{$1} }, [ $message_name, $file, $line ];
         
         } else {
         
            push @{ $referrer{'FEAT'}{$feat} }, [ $message_name, $file, $line ];
         }
      }

   } elsif ( $entityType eq 'ABILITY' ) {

      #[ 1671407 ] xcheck PREABILITY tag
      # Note - shamelessly cut/pasting from the FEAT code, as it's
      # fairly similar.
      ABILITY:
      for my $feat (@list) {

         # We ignore CHECKMULT if used within a PREFEAT tag
         next ABILITY if $feat eq 'CHECKMULT' && $tagName =~ /PREABILITY/;

         # We ignore LIST if used within an ADD:FEAT tag
         next ABILITY if $feat eq 'LIST' && $tagName eq 'ADD:ABILITY';

         # We strip the () if any
         if ( $feat =~ /(.*?[^ ]) ?\((.*)\)/ ) {

            # We check to see if the FEAT is a compond tag
            if ( isValidSubEntity('ABILITY', $1) ) {
               my $original_feat = $feat;
               my $feat_to_check = $feat = $1;
               my $entity              = $2;
               my $sub_tagName  = $tagName;
               $sub_tagName =~ s/@@/$feat (@@)/;

               # Find the real entity type in case of FEAT=
               ABILITY_ENTITY:
               while ( isValidSubEntity('ABILITY', $feat_to_check) =~ /^ABILITY=(.*)/ ) {
                  $feat_to_check = $1;
                  if ( !validSubEntityExists('ABILITY', $feat_to_check) ) {
                     getLogger()->notice(
                        qq{Cannot find the sub-entity for "$original_feat"},
                        $file,
                        $line
                     );
                     $feat_to_check = "";
                     last ABILITY_ENTITY;
                  }
               }

               add_to_xcheck_tables(
                  isValidSubEntity('ABILITY', $feat_to_check),
                  $sub_tagName,
                  $file,
                  $line,
                  $entity
               ) if $feat_to_check && $entity ne 'Ad-Lib';
            }
         }

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$feat/;

         if ( $feat =~ /^TYPE[=.](.*)/ ) {

            push @{ $referrer_types{'ABILITY'}{$1} }, [ $message_name, $file, $line ];
         
         } elsif ( $feat =~ /^CATEGORY[=.](.*)/ ) {
         
            push @{ $referrer_categories{'ABILITY'}{$1} }, [ $message_name, $file, $line ];
         
         } else {
         
            push @{ $referrer{'ABILITY'}{$feat} }, [ $message_name, $file, $line ];
         
         }
      }

   } elsif ( $entityType eq 'KIT STARTPACK' ) {

      for my $kit (@list) {

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$kit/;

         push @{ $referrer{'KIT STARTPACK'}{$kit} }, [ $message_name, $file, $line ];
      }

   } elsif ( $entityType eq 'LANGUAGE' ) {

      for my $language (@list) {

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$language/;

         if ( $language =~ /^TYPE=(.*)/ ) {

            push @{ $referrer_types{'LANGUAGE'}{$1} }, [ $message_name, $file, $line ];
         
         } else {
         
            push @{ $referrer{'LANGUAGE'}{$language} }, [ $message_name, $file, $line ];
         }
      }

   } elsif ( $entityType eq 'MOVE Type' ) {

      MOVE_TYPE:
      for my $move (@list) {

         # The ALL move type is always valid
         next MOVE_TYPE if $move eq 'ALL';

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$move/;

         push @{ $referrer{'MOVE Type'}{$move} }, [ $message_name, $file, $line ]; }

   } elsif ( $entityType eq 'RACE' ) {

      for my $race (@list) {
         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$race/;

         if ( $race =~ / \A TYPE= (.*) /xms ) {

            push @{ $referrer_types{'RACE'}{$1} }, [ $message_name, $file, $line ];
         
         } elsif ( $race =~ / \A RACETYPE= (.*) /xms ) {
         
            push @{ $referrer{'RACETYPE'}{$1} }, [ $message_name, $file, $line ];
         
         } elsif ( $race =~ / \A RACESUBTYPE= (.*) /xms ) {
         
            push @{ $referrer{'RACESUBTYPE'}{$1} }, [ $message_name, $file, $line ];
         
         } else {
         
            push @{ $referrer{'RACE'}{$race} }, [ $message_name, $file, $line ];
         
         }
      }

   } elsif ( $entityType eq 'RACE TYPE' ) {

      for my $race_type (@list) {
         # RACE TYPE is use for TYPE tags in RACE object
         my $message_name = $tagName;
         $message_name =~ s/@@/$race_type/;

         push @{ $referrer_types{'RACE'}{$race_type} }, [ $message_name, $file, $line ];
      }

   } elsif ( $entityType eq 'RACESUBTYPE' ) {

      for my $race_subtype (@list) {
         my $message_name = $tagName;
         $message_name =~ s/@@/$race_subtype/;

         # The RACESUBTYPE can be .REMOVE.<race subtype name>
         $race_subtype =~ s{ \A [.] REMOVE [.] }{}xms;

         push @{ $referrer{'RACESUBTYPE'}{$race_subtype} }, [ $message_name, $file, $line ];
      }

   } elsif ( $entityType eq 'RACETYPE' ) {

      for my $race_type (@list) {
         my $message_name = $tagName;
         $message_name =~ s/@@/$race_type/;

         # The RACETYPE can be .REMOVE.<race type name>
         $race_type =~ s{ \A [.] REMOVE [.] }{}xms;

         push @{ $referrer{'RACETYPE'}{$race_type} }, [ $message_name, $file, $line ];
      }

   } elsif ( $entityType eq 'SKILL' ) {

      SKILL:
      for my $skill (@list) {

         # LIST alone is OK, it is a special variable
         # used to tie in the CHOOSE result
         next SKILL if $skill eq 'LIST';

         # Remove the =level if there is one
         $skill =~ s/(.*)=\d+$/$1/;

         # If there are (), we must verify if it is
         # a compond skill
         if ( $skill =~ /(.*?[^ ]) ?\((.*)\)/ ) {

            # We check to see if the SKILL is a compond tag
            if ( isValidSubEntity('SKILL', $1) ) {
               $skill = $1;
               my $entity = $2;

               my $sub_tagName = $tagName;
               $sub_tagName =~ s/@@/$skill (@@)/;

               add_to_xcheck_tables(
                  isValidSubEntity('SKILL', $skill),
                  $sub_tagName,
                  $file,
                  $line,
                  $entity
               ) if $entity ne 'Ad-Lib';
            }
         }

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$skill/;

         if ( $skill =~ / \A TYPE [.=] (.*) /xms ) {

            push @{ $referrer_types{'SKILL'}{$1} }, [ $message_name, $file, $line ];
         
         } else {
         
            push @{ $referrer{'SKILL'}{$skill} }, [ $message_name, $file, $line ];
         }
      }

   } elsif ( $entityType eq 'SPELL' ) {

      for my $spell (@list) {

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$spell/;

         if ( $spell =~ /^TYPE=(.*)/ ) {
         
            push @{ $referrer_types{'SPELL'}{$1} }, [ $message_name, $file, $line ];
         
         } else {
         
            push @{ $referrer{'SPELL'}{$spell} }, [ $message_name, $file, $line ];
         }
      }

   } elsif ( $entityType eq 'TEMPLATE' ) {

      for my $template (@list) {
         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$template/;

         # We clean up the unwanted stuff
         my $template_copy = $template;
         $template_copy =~ s/ CHOOSE: //xms;
         $message_name =~ s/ CHOOSE: //xms;

         push @{ $referrer{'TEMPLATE'}{$template_copy} }, [ $message_name, $file, $line ];
      }

   } elsif ( $entityType eq 'WEAPONPROF' ) {

      # Nothing is done yet.

   } elsif ( $entityType eq 'SPELL_SCHOOL' || $entityType eq 'Ad-Lib' ) {

      # Nothing is done yet.

   } elsif ( $entityType =~ /,/ ) {

      # There is a , in the name so it is a special
      # validation case that is defered until the validation time.
      # In short, the entry must exists in one of the type list.
      for my $entry (@list) {

         # Put the entry name in place
         my $message_name = $tagName;
         $message_name =~ s/@@/$entry/;

         push @{ $referrer{$entityType}{$entry} }, [ $message_name, $file, $line ];
      }

   } else {
      getLogger()->error(
         "Invalid Entry type for $tagName (add_to_xcheck_tables): $entityType",
         $file,
         $line
      );
   }
}

=head2 _addToReport 

   This operation adds one record to the data structure that will output the
   report about missing tags

=cut

sub _addToReport {
   my ($referrer, $report, $linetype) = @_;

   for my $array_ref ( @{ $referrer } ) {
      my ($name, $file, $line) = @{$array_ref};
      push @{ $report->{$file} }, [ $line, $linetype, $name ];
   }
};

=head2 doXCheck

   Process the the cross check records stored earlier to produce a report.

=cut

sub doXCheck {

   #####################################################
   # First we process the information that must be added
   # to the %referrer and %referrer_types;
   for my $parameter_ref (@{ getCrossCheckData() }) {
      add_to_xcheck_tables( @{$parameter_ref} );
   }

   #####################################################
   # Print a report with the problems found with xcheck

   my %to_report;
   my ($addToReport, $message);

   # Find the entries that need to be reported
   for my $linetype ( sort keys %referrer ) {
      for my $entry ( sort keys %{ $referrer{$linetype} } ) {

         if ( $linetype =~ /,/ ) {

            # Special case if there is a , (comma) in the entry.  We must check
            # multiple possible linetypes.
            my $addToReport = 0;

            ITEM:
            for my $item ( split ',', $linetype ) {

               # ARW 2018/12/10
               # This looks wrong, everything else gets added to the report if its
               # not valid!!! Still this is what pretty lst used to do.

               if (isValidEntity($item, $entry)) {
                  $addToReport = 1;
                  last ITEM;
               }
            }

            # Let's have a cute message
            my @list      = split ',', $linetype;
            my $second    = pop @list;
            my $first     = pop @list;
            my $separator = @list ? ", " : "";

            $message = ( join ', ', @list ) . "${separator}${first} or ${second}"; 

         } else {

            $addToReport = !isValidEntity($linetype, $entry);

            # Special case for EQUIPMOD Key
            # -----------------------------
            # If an EQUIPMOD Key entry doesn't exists, we can use the EQUIPMOD
            # name 
            $message =   ($linetype ne 'EQUIPMOD Key' )      ? $linetype
                       : (isValidEntity('EQUIPMOD', $entry)) ? 'EQUIPMOD Key' 
                       : 'EQUIPMOD Key or EQUIPMOD';
         }

         if ($addToReport) {
            _addToReport($referrer{$linetype}{$entry}, \%to_report, $message); 
         }
      }
   }

   my $log = getLogger();

   # Print the report sorted by file name and line number.
   $log->header(TidyLst::LogHeader::get('CrossRef'));

   # This will add a message for every message in to_report - which should be every message
   # that was added to to_report.
   for my $file ( sort keys %to_report ) {
      for my $line_ref ( sort { $a->[0] <=> $b->[0] } @{ $to_report{$file} } ) {
         my $message = qq{No $line_ref->[1] entry for "$line_ref->[2]"};

         # If it is an EQMOD Key missing, it is less severe
         if ($line_ref->[1] eq 'EQUIPMOD Key') {
            $log->info(  $message, $file, $line_ref->[0] );
         } else {
            $log->notice(  $message, $file, $line_ref->[0] );
         }
      }
   }

   ###############################################
   # Type report
   # This is the code used to change what types are/aren't reported.
   # Find the type entries that need to be reported
   %to_report = ();
   for my $linetype ( sort %referrer_types ) {
      for my $entry ( sort keys %{ $referrer_types{$linetype} } ) {
         if (! isValidType($linetype, $entry) ) {
            for my $array ( @{ $referrer_types{$linetype}{$entry} } ) {
               push @{ $to_report{ $array->[1] } }, [ $array->[2], $linetype, $array->[0] ];
            }
         }
      }
   }

   # Print the type report sorted by file name and line number.
   $log->header(TidyLst::LogHeader::get('Type CrossRef'));

   for my $file ( sort keys %to_report ) {
      for my $line_ref ( sort { $a->[0] <=> $b->[0] } @{ $to_report{$file} } ) {
         $log->notice(
            qq{No $line_ref->[1] type found for "$line_ref->[2]"},
            $file,
            $line_ref->[0]
         );
      }
   }

   ###############################################
   # Category report
   # Needed for full support for [ 1671407 ] xcheck PREABILITY tag
   # Find the category entries that need to be reported
   %to_report = ();
   for my $linetype ( sort %referrer_categories ) {
      for my $entry ( sort keys %{ $referrer_categories{$linetype} } ) {
         if (! isValidCategory($linetype, $entry) ) {
            for my $array ( @{ $referrer_categories{$linetype}{$entry} } ) {
               push @{ $to_report{ $array->[1] } }, [ $array->[2], $linetype, $array->[0] ];
            }
         }
      }
   }

   # Set the header in the singleton logger object
   $log->header(TidyLst::LogHeader::get('Category CrossRef'));

   # Print the category report sorted by file name and line number.
   for my $file ( sort keys %to_report ) {
      for my $line_ref ( sort { $a->[0] <=> $b->[0] } @{ $to_report{$file} } ) {
         $log->notice(
            qq{No $line_ref->[1] category found for "$line_ref->[2]"},
            $file,
            $line_ref->[0]
         );
      }
   }


   #################################
   # Print the tag that do not have defined headers if requested
   if ( getOption('missingheader') ) {

      my $log = getLogger();
      $log->header(TidyLst::LogHeader::get('Missing Header'));

      for my $linetype (sort getMissingHeaderLineTypes()) {

         $log->report("Line Type: ${linetype}");

         for my $header ( sort reportTagSort getHeaderMissingOnLineType()) {
            $log->report("  ${header}");
         }
      }
   }
}


1;
