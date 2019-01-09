#!/usr/bin/perl

use strict;
use warnings;

# Expand the local library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname(abs_path $0) . '/lib';

use TidyLst::Data qw(
   BLOCK BLOCK_HEADER COMMENT FIRST_COLUMN LINE LINE_HEADER MAIN
   NO NO_HEADER SINGLE SUB YES
   );
use TidyLst::Options qw(getOption);

=head2 reformatFile

   Reformat the lines of this file for writing.

=cut

sub reformatFile {

   my ($fileType, $lines) = @_;

   my @newlines = @{ $lines };

   my $tablength = getOption('tabLength');

   # Now on to all the non header lines.
   CORE_LINE:
   for ( my $line_index = 0; $line_index < @newlines; $line_index++ ) {

      # We skip any text or header lines
      if (ref( $newlines[$line_index] ) ne 'ARRAY' || $newlines[$line_index][0] eq 'HEADER') {
         next CORE_LINE
      }

      my $line_ref = $newlines[$line_index];

      my ($curent_linetype, $line_tokens, $last_main_line, $curent_entity, $line_info, $line) = @$line_ref;

      my $newline = "";

      # If the separator is not a tab, with just join the
      # tag in order
      my $sep = $line_info->{Sep} || "\t";

      if ( $sep ne "\t" ) {

         # First, deal with the tags in masterOrder
         for my $tag ( @{getOrderForLineType($line->type)} ) {
            if ( exists $line_tokens->{$tag} ) {
               $newline .= join $sep, @{ $line_tokens->{$tag} };
               $newline .= $sep;
               delete $line_tokens->{$tag};
            }
         }

         # The remaining tags are not in the masterOrder list
         for my $tag ( sort keys %$line_tokens ) {
            $newline .= join $sep, @{ $line_tokens->{$tag} };
            $newline .= $sep;
         }

         # We remove the extra separator
         for ( my $i = 0; $i < length($sep); $i++ ) {
            chop $newline;
         }

         # We replace line_ref with the new line
         $newlines[$line_index] = $newline;
         next CORE_LINE;
      }

      ##################################################
      # The line must be formatted according to its
      # TYPE, FORMAT and HEADER parameters.

      my $mode   = $line_info->{Mode};
      my $format = $line_info->{Format};
      my $header = $line_info->{Header};

      if ( $mode == SINGLE || $format == LINE ) {

         # LINE: the line if formatted independently.
         #               The FORMAT is ignored.
         if ( $header == NO_HEADER ) {

            # Just put the line in order and with a single tab
            # between the columns. If there is a header in the previous
            # line, we remove it.

            # First, the tag known in masterOrder
            for my $tag ( @{getOrderForLineType($line->type)} ) {
               if ( exists $line_tokens->{$tag} ) {
                  $newline .= join $sep, @{ $line_tokens->{$tag} };
                  $newline .= $sep;
                  delete $line_tokens->{$tag};
               }
            }

            # The remaining tag are not in the masterOrder list
            for my $tag ( sort keys %$line_tokens ) {
               $newline .= join $sep, @{ $line_tokens->{$tag} };
               $newline .= $sep;
            }

            # We remove the extra separator
            for ( my $i = 0; $i < length($sep); $i++ ) {
               chop $newline;
            }

            # If there was an header before this line, we remove it
            if (ref($newlines[ $line_index - 1 ]) eq 'ARRAY' && $newlines[ $line_index - 1 ][0] eq 'HEADER' ) {

               splice( @newlines, $line_index - 1, 1 );
               $line_index--;
            }

            # Replace the array with the new line
            $newlines[$line_index] = $newline;
            next CORE_LINE;

         } elsif ( $header == LINE_HEADER ) {

            # Put the line with a header in front of it.
            my %col_length  = ();
            my $header_line = "";
            my $line_entity = "";

            # Find the length for each column
            $col_length{$_} = mylength( $line_tokens->{$_} ) for ( keys %$line_tokens );

            # Find the columns order and build the header and
            # the curent line
            TAG_NAME:
            for my $tag ( @{getOrderForLineType($line->type)} ) {

               # We skip if the tag is not present in the line
               next TAG_NAME if !exists $col_length{$tag};

               # The first tag is the line entity and must be kept
               $line_entity = $line_tokens->{$tag}[0] unless $line_entity;

               # What is the length of the column?
               my $header_text   = getHeader( $tag, $line->type );
               my $header_length = mylength($header_text);
               my $col_length    = $header_length > $col_length{$tag} ? $header_length : $col_length{$tag};

               # Round the col_length up to the next tab
               $col_length = $tablength * ( int( $col_length / $tablength ) + 1 );

               # The header
               my $tab_to_add = int(($col_length - $header_length) / $tablength) + (($col_length - $header_length) % $tablength ? 1 : 0);
               $header_line .= $header_text . $sep x $tab_to_add;

               # The line
               $tab_to_add = int(($col_length - $col_length{$tag}) / $tablength) + (($col_length - $col_length{$tag}) % $tablength ? 1 : 0);
               $newline .= join $sep, @{ $line_tokens->{$tag} };
               $newline .= $sep x $tab_to_add;

               # Remove the tag we just dealt with
               delete $line_tokens->{$tag};
            }

            # Add the tags that were not in the masterOrder
            for my $tag ( sort keys %$line_tokens ) {

               # What is the length of the column?
               my $header_text   = getHeader( $tag, $line->type );
               my $header_length = mylength($header_text);
               my $col_length  = $header_length > $col_length{$tag} ? $header_length : $col_length{$tag};

               # Round the col_length up to the next tab
               $col_length = $tablength * ( int( $col_length / $tablength ) + 1 );

               # The header
               my $tab_to_add = int(($col_length - $header_length) / $tablength) + (($col_length - $header_length) % $tablength ? 1 : 0 );
               $header_line .= $header_text . $sep x $tab_to_add;

               # The line
               $tab_to_add = int(($col_length - $col_length{$tag}) / $tablength) + (($col_length - $col_length{$tag}) % $tablength ? 1 : 0 );
               $newline .= join $sep, @{ $line_tokens->{$tag} };
               $newline .= $sep x $tab_to_add;
            }

            # Remove the extra separators (tabs) at the end of both lines
            $header_line =~ s/$sep$//g;
            $newline        =~ s/$sep$//g;

            # Put the header in place
            if (ref($newlines[$line_index - 1]) eq 'ARRAY' && $newlines[$line_index - 1][0] eq 'HEADER' ) {

               # We replace the existing header
               $newlines[ $line_index - 1 ] = $header_line;

            } else {

               # We add the header before the line
               splice( @newlines, $line_index++, 0, $header_line );
            }

            # Add an empty line in front of the header unless there is already
            # one or the previous line matches the line entity.
            if ($newlines[$line_index - 2] ne '' && index($newlines[$line_index - 2], $line_entity) != 0) {

               splice( @newlines, $line_index - 1, 0, '' );
               $line_index++;
            }

            # Replace the array with the new line
            $newlines[$line_index] = $newline;
            next CORE_LINE;

         } else {

            # Invalid option
            die qq(Invalid \%TidyLst::Parse::parseControl options: $fileType:") . $line->type . qq(":$mode:$header);
         }

      } elsif ( $mode == MAIN ) {

         if ( $format == BLOCK ) {

            #####################################
            # All the main lines must be found up until a different main line
            # type or a ###Block comment.
            
            my @main_lines;
            my $main_linetype = $line->type;

            BLOCK_LINE:
            for ( my $index = $line_index; $index < @newlines; $index++ ) {

               # If the line_type changes or if a '###Block'
               # comment is found, we are out of the block

               last BLOCK_LINE
               if (ref $newlines[$index] eq 'ARRAY'
                  && ref $newlines[$index][4] eq 'HASH'
                  && $newlines[$index][4]{Mode} == MAIN
                  && $newlines[$index][0] ne $main_linetype )
               || (ref $newlines[$index] ne 'ARRAY' && index( lc( $newlines[$index] ), '###block' ) == 0 );

               # Skip the lines already dealt with
               if (ref($newlines[$index]) ne 'ARRAY' || $newlines[$index][0] eq 'HEADER') {
                  next BLOCK_LINE
               }

               if ($newlines[$index][4]{Mode} == MAIN) {
                  push @main_lines, $index
               }
            }

            #####################################
            # We find the length of each tag for the block
            my %col_length;
            for my $block_line (@main_lines) {
               for my $tag (keys %{ $newlines[$block_line][1] }) {
                  my $col_length = mylength($newlines[$block_line][1]{$tag});

                  if (!exists $col_length{$tag} || $col_length > $col_length{$tag}) {
                     $col_length{$tag} = $col_length
                  }
               }
            }

            if ( $header != NO_HEADER ) {

               # We add the length of the headers if needed.
               for my $tag ( keys %col_length ) {
                  my $length = mylength( getHeader( $tag, $fileType ) );

                  $col_length{$tag} = $length if $length > $col_length{$tag};
               }
            }

            #####################################
            # Find the columns order
            my %seen;
            my @col_order;

            # First, the columns included in masterOrder
            for my $tag (@{getOrderForLineType($line->type)}) {
               push @col_order, $tag if exists $col_length{$tag};
               $seen{$tag}++;
            }

            # Put the unknown columns at the end
            for my $tag ( sort keys %col_length ) {
               push @col_order, $tag unless $seen{$tag};
            }

            # Each of the block lines must be reformated
            for my $block_line (@main_lines) {
               my $newline;

               for my $tag (@col_order) {

                  my $col_max_length = $tablength * (int($col_length{$tag} / $tablength) + 1);

                  # Is the tag present in this line?
                  if ( exists $newlines[$block_line][1]{$tag} ) {
                     my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                     my $tab_to_add = int(($col_max_length - $curent_length) / $tablength) + (($col_max_length - $curent_length) % $tablength ? 1 : 0 );
                     $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                     $newline .= $sep x $tab_to_add;

                  } else {

                     # We pad with tabs
                     $newline .= $sep x ( $col_max_length / $tablength );
                  }
               }

               # We remove the extra $sep at the end
               $newline =~ s/$sep+$//;

               # We replace the array with the new line
               $newlines[$block_line] = $newline;
            }

            if ( $header == NO_HEADER ) {

               # If there are header before any of the block line,
               # we need to remove them
               for my $block_line (reverse @main_lines) {

                  if (ref $newlines[$block_line - 1] eq 'ARRAY' && $newlines[$block_line - 1][0] eq 'HEADER' ) {

                     splice( @newlines, $block_line - 1, 1 );
                     $line_index--;
                  }
               }

            } elsif ( $header == LINE_HEADER ) {

               die "MAIN:BLOCK:LINE_HEADER not implemented yet";

            } elsif ( $header == BLOCK_HEADER ) {

               # We must add the header line at the top of the block
               # and anywhere else we find them whitin the block.

               my $header_line;
               for my $tag (@col_order) {

                  # Round the col_length up to the next tab
                  my $col_max_length = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                  my $curent_header = getHeader( $tag, $main_linetype );
                  my $curent_length = mylength($curent_header);
                  my $tab_to_add  = int(($col_max_length - $curent_length) / $tablength) + (($col_max_length - $curent_length) % $tablength ? 1 : 0 );
                  $header_line .= $curent_header . $sep x $tab_to_add;
               }

               # We remove the extra $sep at the end
               $header_line =~ s/$sep+$//;

               # Before the top of the block
               my $need_top_header = NO;
               if (ref $newlines[$main_lines[0] - 1] ne 'ARRAY' || $newlines[$main_lines[0] - 1][0] ne 'HEADER' )
               {
                  $need_top_header = YES;
               }

               # Anywhere in the block
               for my $block_line (@main_lines) {
                  if (ref $newlines[$block_line - 1] eq 'ARRAY' && $newlines[$block_line - 1][0] eq 'HEADER' ) {
                     $newlines[$block_line - 1] = $header_line;
                  }
               }

               # Add a header line at the top of the block
               if ($need_top_header) {
                  splice( @newlines, $main_lines[0], 0, $header_line );
                  $line_index++;
               }

            }

         } else {
            die qq(Invalid \%TidyLst::Parse::parseControl format: $fileType:") . $line->type . q(":$mode:$header);
         }

      } elsif ( $mode == SUB ) {

         if ( $format == LINE ) {

            die "SUB:LINE not implemented yet";

         } elsif ( $format == BLOCK || $format == FIRST_COLUMN ) {

            #####################################
            # Need to find all the file in the SUB BLOCK i.e. same line type
            # within two MAIN lines.
            # If we encounter a ###Block comment, that's the end of the block

            my @sub_lines;
            my $begin_block  = $line->lastMain;
            my $sub_linetype = $line->type;

            BLOCK_LINE:
            for ( my $index = $line_index; $index < @newlines; $index++ ) {

               # If the line->lastMain change or
               # if a '###Block' comment is found,
               # we are out of the block
               if ((ref $newlines[$index] eq 'ARRAY' && $newlines[$index][0] ne 'HEADER' && $newlines[$index][2] != $begin_block)
                  || (ref $newlines[$index] ne 'ARRAY' && index(lc $newlines[$index], '###block') == 0)) {
                  last BLOCK_LINE
               }

               # Skip the lines already dealt with
               if (ref( $newlines[$index] ) ne 'ARRAY' || $newlines[$index][0] eq 'HEADER') {
                  next BLOCK_LINE
               }

               if ($newlines[$index][0] eq $line->type) {
                  push @sub_lines, $index
               }
            }

            #####################################
            # We find the length of each tag for the block
            my %col_length;
            for my $block_line (@sub_lines) {
               for my $tag ( keys %{ $newlines[$block_line][1] } ) {

                  my $col_length = mylength( $newlines[$block_line][1]{$tag} );

                  if (!exists $col_length{$tag} || $col_length > $col_length{$tag}) {
                     $col_length{$tag} = $col_length
                  }
               }
            }

            if ( $header == BLOCK_HEADER ) {

               # We add the length of the headers if needed.
               for my $tag ( keys %col_length ) {
                  my $length = mylength( getHeader( $tag, $fileType ) );

                  if ($length > $col_length{$tag}) {
                     $col_length{$tag} = $length 
                  }
               }
            }

            #####################################
            # Find the columns order
            my %seen;
            my @col_order;

            # First, the columns included in masterOrder
            for my $tag ( @{getOrderForLineType($line->type)} ) {
               push @col_order, $tag 
               if (exists $col_length{$tag}) {
                  $seen{$tag}++;
               }
            }

            # Put the unknown columns at the end
            for my $tag (sort keys %col_length) {
               unless ($seen{$tag}) {
                  push @col_order, $tag 
               }
            }

            # Each of the block lines must be reformated
            if ( $format == BLOCK ) {
               for my $block_line (@sub_lines) {
                  my $newline;

                  for my $tag (@col_order) {
                     my $col_max_length
                     = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );

                     # Is the tag present in this line?
                     if ( exists $newlines[$block_line][1]{$tag} ) {
                        my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                        my $tab_to_add
                        = int( ( $col_max_length - $curent_length ) / $tablength )
                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                        $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                        $newline .= $sep x $tab_to_add;
                     }
                     else {

                        # We pad with tabs
                        $newline .= $sep x ( $col_max_length / $tablength );
                     }
                  }

                                # We replace the array with the new line
                                $newlines[$block_line] = $newline;
                                }
                        }
                        else {

                                # $format == FIRST_COLUMN

                                for my $block_line (@sub_lines) {
                                my $newline;
                                my $first_column = YES;
                                my $tab_to_add;

                                TAG:
                                for my $tag (@col_order) {

                                        # Is the tag present in this line?
                                        next TAG if !exists $newlines[$block_line][1]{$tag};

                                        if ($first_column) {
                                                my $col_max_length
                                                = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                                my $curent_length = mylength( $newlines[$block_line][1]{$tag} );

                                                $tab_to_add
                                                = int( ( $col_max_length - $curent_length ) / $tablength )
                                                + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );

                                                # It's no longer the first column
                                                $first_column = NO;
                                        }
                                        else {
                                                $tab_to_add = 1;
                                        }

                                        $newline .= join $sep, @{ $newlines[$block_line][1]{$tag} };
                                        $newline .= $sep x $tab_to_add;
                                }

                                # We replace the array with the new line
                                $newlines[$block_line] = $newline;
                                }
                        }

                        if ( $header == NO_HEADER ) {

                                # If there are header before any of the block line,
                                # we need to remove them
                                for my $block_line ( reverse @sub_lines ) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        splice( @newlines, $block_line - 1, 1 );
                                        $line_index--;
                                }
                                }
                        }
                        elsif ( $header == LINE_HEADER ) {
                                die "SUB:BLOCK:LINE_HEADER not implemented yet";
                        }
                        elsif ( $header == BLOCK_HEADER ) {

                                # We must add the header line at the top of the block
                                # and anywhere else we find them whitin the block.

                                my $header_line;
                                for my $tag (@col_order) {

                                # Round the col_length up to the next tab
                                my $col_max_length
                                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                my $curent_header = getHeader( $tag, $sub_linetype );
                                my $curent_length = mylength($curent_header);
                                my $tab_to_add  = int( ( $col_max_length - $curent_length ) / $tablength )
                                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                $header_line .= $header . $sep x $tab_to_add;
                                }

                                # Before the top of the block
                                my $need_top_header = NO;
                                if ( ref( $newlines[ $sub_lines[0] - 1 ] ) ne 'ARRAY'
                                || $newlines[ $sub_lines[0] - 1 ][0] ne 'HEADER' )
                                {
                                $need_top_header = YES;
                                }

                                # Anywhere in the block
                                for my $block_line (@sub_lines) {
                                if ( ref( $newlines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $newlines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        $newlines[ $block_line - 1 ] = $header_line;
                                }
                                }

                                # Add a header line at the top of the block
                                if ($need_top_header) {
                                splice( @newlines, $sub_lines[0], 0, $header_line );
                                $line_index++;
                                }

                        }
                        else {
                                die qq(Invalid \%TidyLst::Parse::parseControl ") . $line->type . q(":$mode:$format:$header);
                        }
                } else {
                        die qq(Invalid \%TidyLst::Parse::parseControl ") . $line->type . q(":$mode:$format:$header);
                }
                } else {
                die qq(Invalid \%TidyLst::Parse::parseControl mode: $fileType:") . $line->type . q(":$mode);
                }

        }

        # If there are header lines remaining, we keep the old value
        for (@newlines) {
                $_ = $_->[1] if ref($_) eq 'ARRAY' && $_->[0] eq 'HEADER';
        }

        return \@newlines;

}
