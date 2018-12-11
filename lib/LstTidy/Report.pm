package LstTidy::Report;

use strict;
use warnings;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

# predeclare this so we can call it without & or trailing () like a builtin
sub report_tag_sort;

# Will hold the information for the entries that must be added in %referrer or
# %referrer_types. The array is needed because all the files must have been
# parsed before processing the information to be added.  The function
# add_to_xcheck_tables will be called with each line of the array.
our @xcheck_to_process;  

# Will hold the tags that refer to other entries
# Format: push @{$referrer{$EntityType}{$entryname}}, [ $tags{$column}, $file_for_error, $line_for_error ]
my %referrer;

# Will hold the categories used by abilities to allow validation;
# [ 1671407 ] xcheck PREABILITY tag
my %referrer_categories;

# Will hold the type used by some of the tags to allow validation.
# Format: push @{$referrer_types{$EntityType}{$typename}}, [ $tags{$column}, $file_for_error, $line_for_error ]
my %referrer_types;

my %valid_sub_entities;

# Will hold the number of each tag found (by linetype)
my %count_tags;

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

sub incCountValidTags {
   my ($lineType, $tag) = @_;

   $count_tags{"Valid"}{"Total"}{$tag}++;
   $count_tags{"Valid"}{$lineType}{$tag}++;
}

sub incCountInvalidTags {
   my ($lineType, $tag) = @_;

   $count_tags{"Invalid"}{"Total"}{$tag}++;
   $count_tags{"Invalid"}{$lineType}{$tag}++;
}

=head2 foundInvalidTags

   Returns true if any invalid tags were found while processing the lst files.

=cut

sub foundInvalidTags {
   return exists $count_tags{"Invalid"};
}

=head2 reportValid
   
   Print a report for the number of tags found.
   
=cut

sub reportValid {

   print STDERR "\n================================================================\n";
   print STDERR "Valid tags found\n";
   print STDERR "----------------------------------------------------------------\n";

   my $first = 1;
   REPORT_LINE_TYPE:
   for my $line_type ( sort keys %{ $count_tags{"Valid"} } ) {
      next REPORT_LINE_TYPE if $line_type eq "Total";

      print STDERR "\n" unless $first;
      print STDERR "Line Type: $line_type\n";

      for my $tag ( sort report_tag_sort keys %{ $count_tags{"Valid"}{$line_type} } ) {

         my $tagdisplay = $tag;
         $tagdisplay .= "*" if LstTidy::Reformat::isValidMultiTag($line_type, $tag);
         my $line = "    $tagdisplay";
         $line .= ( " " x ( 26 - length($tagdisplay) ) ) . $count_tags{"Valid"}{$line_type}{$tag};

         print STDERR "$line\n";
      }

      $first = 0;
   }

   print STDERR "\nTotal:\n";

   for my $tag ( sort report_tag_sort keys %{ $count_tags{"Valid"}{"Total"} } ) {

      my $line = "    $tag";
      $line .= ( " " x ( 26 - length($tag) ) ) . $count_tags{"Valid"}{"Total"}{$tag};

      print STDERR "$line\n";
   }
}




=head2 reportInvalid


=cut


sub reportInvalid {

   print STDERR "\n================================================================\n";
   print STDERR "Invalid tags found\n";
   print STDERR "----------------------------------------------------------------\n";

   my $first = 1;
   INVALID_LINE_TYPE:
   for my $linetype ( sort keys %{ $count_tags{"Invalid"} } ) {

      next INVALID_LINE_TYPE if $linetype eq "Total";

      print STDERR "\n" unless $first;
      print STDERR "Line Type: $linetype\n";

      for my $tag ( sort report_tag_sort keys %{ $count_tags{"Invalid"}{$linetype} } ) {

         my $line = "    $tag";
         $line .= ( " " x ( 26 - length($tag) ) ) . $count_tags{"Invalid"}{$linetype}{$tag};
         print STDERR "$line\n";
      }

      $first = 0;
   }

   print STDERR "\nTotal:\n";

   for my $tag ( sort report_tag_sort keys %{ $count_tags{"Invalid"}{"Total"} } ) {

      my $line = "    $tag";
      $line .= ( " " x ( 26 - length($tag) ) ) . $count_tags{"Invalid"}{"Total"}{$tag};
      print STDERR "$line\n";

   }
}



=head2 report_tag_sort

   Sort used for the tag when reporting them.

   Basicaly, it's a normal ASCII sort except that the ! are removed when found
   (the PRExxx and !PRExxx are sorted one after the other).

=cut

sub report_tag_sort {
   my ( $left, $right ) = ( $a, $b );      # We need a copy in order to modify

   # Remove the !. $not_xxx contains 1 if there was a !, otherwise
   # it contains 0.
   my $not_left  = $left  =~ s{^!}{}xms;
   my $not_right = $right =~ s{^!}{}xms;

   $left cmp $right || $not_left <=> $not_right;
}




=head2 registerXCheck

   Register this data for later cross checking

=cut

sub registerXCheck {
   my ($preType, $tag, $file, $line, @values) = @_;
   
   push @xcheck_to_process, [ $preType, $tag, $file, $line, @values ];
}


=head2 registerReferrer

   Register this data for later cross checking

=cut

sub registerReferrer {
   my ($linetype, $entity_name, $token, $file, $line) = @_;

   push @{ $referrer{$linetype}{$entity_name} }, [ $token, $file, $line ]
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
   @list = grep { $_ ne "" } @list;

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
            if ( $valid_sub_entities{'FEAT'}{$1} ) {
               my $original_feat = $feat;
               my $feat_to_check = $feat = $1;
               my $entity              = $2;
               my $sub_tagName  = $tagName;
               $sub_tagName =~ s/@@/$feat (@@)/;

               # Find the real entity type in case of FEAT=
               FEAT_ENTITY:
               while ( $valid_sub_entities{'FEAT'}{$feat_to_check} =~ /^FEAT=(.*)/ ) {
                  $feat_to_check = $1;
                  if ( !exists $valid_sub_entities{'FEAT'}{$feat_to_check} ) {
                     LstTidy::LogFactory::getLogger()->notice(
                        qq{Cannot find the sub-entity for "$original_feat"},
                        $file,
                        $line
                     );
                     $feat_to_check = "";
                     last FEAT_ENTITY;
                  }
               }

               add_to_xcheck_tables(
                  $valid_sub_entities{'FEAT'}{$feat_to_check},
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

         # We stript the () if any
         if ( $feat =~ /(.*?[^ ]) ?\((.*)\)/ ) {

            # We check to see if the FEAT is a compond tag
            if ( $valid_sub_entities{'ABILITY'}{$1} ) {
               my $original_feat = $feat;
               my $feat_to_check = $feat = $1;
               my $entity              = $2;
               my $sub_tagName  = $tagName;
               $sub_tagName =~ s/@@/$feat (@@)/;

               # Find the real entity type in case of FEAT=
               ABILITY_ENTITY:
               while ( $valid_sub_entities{'ABILITY'}{$feat_to_check} =~ /^ABILITY=(.*)/ ) {
                  $feat_to_check = $1;
                  if ( !exists $valid_sub_entities{'ABILITY'}{$feat_to_check} ) {
                     LstTidy::LogFactory::getLogger()->notice(
                        qq{Cannot find the sub-entity for "$original_feat"},
                        $file,
                        $line
                     );
                     $feat_to_check = "";
                     last ABILITY_ENTITY;
                  }
               }

               add_to_xcheck_tables(
                  $valid_sub_entities{'ABILITY'}{$feat_to_check},
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
            if ( $valid_sub_entities{'SKILL'}{$1} ) {
               $skill = $1;
               my $entity = $2;

               my $sub_tagName = $tagName;
               $sub_tagName =~ s/@@/$skill (@@)/;

               add_to_xcheck_tables(
                  $valid_sub_entities{'SKILL'}{$skill},
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
      LstTidy::LogFactory::getLogger()->error(
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

   Precoess the the cross check resords stored earlier to produce a report.

=cut

sub doXCheck {

   #####################################################
   # First we process the information that must be added
   # to the %referrer and %referrer_types;
   for my $parameter_ref (@xcheck_to_process) {
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

               if (LstTidy::Validate::isEntityValid($item, $entry)) {
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

            $addToReport = !LstTidy::Validate::isEntityValid($linetype, $entry);

            # Special case for EQUIPMOD Key
            # -----------------------------
            # If an EQUIPMOD Key entry doesn't exists, we can use the EQUIPMOD
            # name 
            $message =   ($linetype ne 'EQUIPMOD Key' )                         ? $linetype
                       : (LstTidy::Validate::isEntityValid('EQUIPMOD', $entry)) ? 'EQUIPMOD Key' 
                       : 'EQUIPMOD Key or EQUIPMOD';
         }

         if ($addToReport) {
            _addToReport($referrer{$linetype}{$entry}, \%to_report, $message); 
         }
      }
   }

   my $logger = LstTidy::LogFactory::getLogger();

   # Print the report sorted by file name and line number.
   $logger->header(LstTidy::LogHeader::get('CrossRef'));

   # This will add a message for every message in to_report - which should be every message
   # that was added to to_report.
   for my $file ( sort keys %to_report ) {
      for my $line_ref ( sort { $a->[0] <=> $b->[0] } @{ $to_report{$file} } ) {
         my $message = qq{No $line_ref->[1] entry for "$line_ref->[2]"};

         # If it is an EQMOD Key missing, it is less severe
         if ($line_ref->[1] eq 'EQUIPMOD Key') {
            $logger->info(  $message, $file, $line_ref->[0] );
         } else {
            $logger->notice(  $message, $file, $line_ref->[0] );
         }
      }
   }
   
   my %valid_types = LstTidy::Validate::getValidTypes();

   ###############################################
   # Type report
   # This is the code used to change what types are/aren't reported.
   # Find the type entries that need to be reported
   %to_report = ();
   for my $linetype ( sort %referrer_types ) {
      for my $entry ( sort keys %{ $referrer_types{$linetype} } ) {
         if (! exists $valid_types{$linetype}{$entry} ) {
            for my $array ( @{ $referrer_types{$linetype}{$entry} } ) {
               push @{ $to_report{ $array->[1] } }, [ $array->[2], $linetype, $array->[0] ];
            }
         }
      }
   }

   # Print the type report sorted by file name and line number.
   $logger->header(LstTidy::LogHeader::get('Type CrossRef'));

   for my $file ( sort keys %to_report ) {
      for my $line_ref ( sort { $a->[0] <=> $b->[0] } @{ $to_report{$file} } ) {
         $logger->notice(
            qq{No $line_ref->[1] type found for "$line_ref->[2]"},
            $file,
            $line_ref->[0]
         );
      }
   }
   
   my %valid_categories = LstTidy::Validate::getValidCategories();

   ###############################################
   # Category report
   # Needed for full support for [ 1671407 ] xcheck PREABILITY tag
   # Find the category entries that need to be reported
   %to_report = ();
   for my $linetype ( sort %referrer_categories ) {
      for my $entry ( sort keys %{ $referrer_categories{$linetype} } ) {
         if (!exists $valid_categories{$linetype}{$entry} ) {
            for my $array ( @{ $referrer_categories{$linetype}{$entry} } ) {
               push @{ $to_report{ $array->[1] } }, [ $array->[2], $linetype, $array->[0] ];
            }
         }
      }
   }

   # Set the header in the singleton logger object
   $logger->header(LstTidy::LogHeader::get('Category CrossRef'));

   # Print the category report sorted by file name and line number.
   for my $file ( sort keys %to_report ) {
      for my $line_ref ( sort { $a->[0] <=> $b->[0] } @{ $to_report{$file} } ) {
         $logger->notice(
            qq{No $line_ref->[1] category found for "$line_ref->[2]"},
            $file,
            $line_ref->[0]
         );
      }
   }


   #################################
   # Print the tag that do not have defined headers if requested
   if ( getOption('missingheader') ) {

      my $logger = LstTidy::LogFactory::getLogger();
      $logger->header(LstTidy::LogHeader::get('Missing Header'));

      my %missing_headers = %{ LstTidy::Parse::getMissingHeaders() };

      for my $linetype ( sort keys %missing_headers ) {

         $logger->report("Line Type: ${linetype}");

         for my $header ( sort report_tag_sort keys %{ $missing_headers{$linetype} } ) {
            $logger->report("  ${header}");
         }
      }
   }
}


1;
