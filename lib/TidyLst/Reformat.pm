package TidyLst::Reformat;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   );

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);
 
use TidyLst::Formater;
use TidyLst::Options qw(getOption);

=head2 reformatFile

   Reformat the lines of this file for writing.

=cut

sub reformatFile {

   my ($fileType, $lines) = @_;

   my @oldLines = @{ $lines };
   my @newLInes;

   my $tabLength = getOption('tabLength');

   CORE_LINE:
   for my $lineRef (@{ $lines }) {
      if (ref $lineRef ne 'ARRAY' || ${ $lineRef }[0] eq 'HEADER' ) {
         push @newLines, $lineRef;
         next CORE_LINE
      }

      my $line = @{$lineRef}[-1];
      my $info = @{$lineRef}[-2];
      my $newline = "";

      my $mode   = $info->{Mode};
      my $format = $info->{Format};
      my $header = $info->{Header};

      if ( $mode == SINGLE || $format == LINE ) {

         my $formatter = TidyLst::Formatter->new(type => $line->type);
         $formatter->adjustLengths($line);

         # if the previous line was a header, remove it.
         if (ref $newLines[-1] ne 'ARRAY' || $newLines[-1][0] eq 'HEADER' ) {
            pop @newLines;
         }

         if ( $header == NO_HEADER ) {
         
            push @newLines, $formatter->constructLine($line, $tabLength);
            next CORE_LINE

         } elsif ( $header == LINE_HEADER ) {

            # Add an empty line in front of the header unless there is already
            # one or the previous line matches the line entity.
            my $previous;
            if (ref $newLines[-1] ne 'ARRAY') {
               $previous = index($newLines[-1], $line->entity) == 0;
            }

            if ( ! $previous || (ref $newLines[-1] ne 'ARRAY' && $newLines[-1] ne '')) {
         
               push @newLines, q();
            }

            $formatter->adjustLengthsForHeaders($line);

            push @newLines, $formatter->constructHeaderLine($line, $tabLength);
            push @newLines, $formatter->constructLine($line, $tabLength);

         } else {

            # Invalid option
            die qq(Invalid \%TidyLst::Parse::parseControl options: $fileType:) 
            . $line->type . qq(:$mode:$header);
         }





      } elsif ( $mode == MAIN ) {

         if ( $format == BLOCK ) {

            #####################################
            # All the main lines must be found up until a different main line
            # type or a ###Block comment.
            
            my @main_lines;
            my $main_linetype = $line->type;

            BLOCK_LINE:
            for ( my $index = $line_index; $index < @oldLines; $index++ ) {

               # If the line_type changes or if a '###Block'
               # comment is found, we are out of the block

               last BLOCK_LINE
               if (ref $oldLines[$index] eq 'ARRAY'
                  && ref $oldLines[$index][4] eq 'HASH'
                  && $oldLines[$index][4]{Mode} == MAIN
                  && $oldLines[$index][0] ne $main_linetype )
               || (ref $oldLines[$index] ne 'ARRAY' && index( lc( $oldLines[$index] ), '###block' ) == 0 );

               # Skip the lines already dealt with
               if (ref($oldLines[$index]) ne 'ARRAY' || $oldLines[$index][0] eq 'HEADER') {
                  next BLOCK_LINE
               }

               if ($oldLines[$index][4]{Mode} == MAIN) {
                  push @main_lines, $index
               }
            }

            #####################################
            # We find the length of each tag for the block
            my %col_length;
            for my $block_line (@main_lines) {
               for my $tag (keys %{ $oldLines[$block_line][1] }) {
                  my $col_length = mylength($oldLines[$block_line][1]{$tag});

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
                  if ( exists $oldLines[$block_line][1]{$tag} ) {
                     my $curent_length = mylength( $oldLines[$block_line][1]{$tag} );

                     my $tab_to_add = int(($col_max_length - $curent_length) / $tablength) + (($col_max_length - $curent_length) % $tablength ? 1 : 0 );
                     $newline .= join $sep, @{ $oldLines[$block_line][1]{$tag} };
                     $newline .= $sep x $tab_to_add;

                  } else {

                     # We pad with tabs
                     $newline .= $sep x ( $col_max_length / $tablength );
                  }
               }

               # We remove the extra $sep at the end
               $newline =~ s/$sep+$//;

               # We replace the array with the new line
               $oldLines[$block_line] = $newline;
            }

            if ( $header == NO_HEADER ) {

               # If there are header before any of the block line,
               # we need to remove them
               for my $block_line (reverse @main_lines) {

                  if (ref $oldLines[$block_line - 1] eq 'ARRAY' && $oldLines[$block_line - 1][0] eq 'HEADER' ) {

                     splice( @oldLines, $block_line - 1, 1 );
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
               if (ref $oldLines[$main_lines[0] - 1] ne 'ARRAY' || $oldLines[$main_lines[0] - 1][0] ne 'HEADER' )
               {
                  $need_top_header = YES;
               }

               # Anywhere in the block
               for my $block_line (@main_lines) {
                  if (ref $oldLines[$block_line - 1] eq 'ARRAY' && $oldLines[$block_line - 1][0] eq 'HEADER' ) {
                     $oldLines[$block_line - 1] = $header_line;
                  }
               }

               # Add a header line at the top of the block
               if ($need_top_header) {
                  splice( @oldLines, $main_lines[0], 0, $header_line );
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
            for ( my $index = $line_index; $index < @oldLines; $index++ ) {

               # If the line->lastMain change or
               # if a '###Block' comment is found,
               # we are out of the block
               if ((ref $oldLines[$index] eq 'ARRAY' && $oldLines[$index][0] ne 'HEADER' && $oldLines[$index][2] != $begin_block)
                  || (ref $oldLines[$index] ne 'ARRAY' && index(lc $oldLines[$index], '###block') == 0)) {
                  last BLOCK_LINE
               }

               # Skip the lines already dealt with
               if (ref( $oldLines[$index] ) ne 'ARRAY' || $oldLines[$index][0] eq 'HEADER') {
                  next BLOCK_LINE
               }

               if ($oldLines[$index][0] eq $line->type) {
                  push @sub_lines, $index
               }
            }

            #####################################
            # We find the length of each tag for the block
            my %col_length;
            for my $block_line (@sub_lines) {
               for my $tag ( keys %{ $oldLines[$block_line][1] } ) {

                  my $col_length = mylength( $oldLines[$block_line][1]{$tag} );

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
                     if ( exists $oldLines[$block_line][1]{$tag} ) {
                        my $curent_length = mylength( $oldLines[$block_line][1]{$tag} );

                        my $tab_to_add
                        = int( ( $col_max_length - $curent_length ) / $tablength )
                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                        $newline .= join $sep, @{ $oldLines[$block_line][1]{$tag} };
                        $newline .= $sep x $tab_to_add;
                     }
                     else {

                        # We pad with tabs
                        $newline .= $sep x ( $col_max_length / $tablength );
                     }
                  }

                                # We replace the array with the new line
                                $oldLines[$block_line] = $newline;
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
                                        next TAG if !exists $oldLines[$block_line][1]{$tag};

                                        if ($first_column) {
                                                my $col_max_length
                                                = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                                my $curent_length = mylength( $oldLines[$block_line][1]{$tag} );

                                                $tab_to_add
                                                = int( ( $col_max_length - $curent_length ) / $tablength )
                                                + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );

                                                # It's no longer the first column
                                                $first_column = NO;
                                        }
                                        else {
                                                $tab_to_add = 1;
                                        }

                                        $newline .= join $sep, @{ $oldLines[$block_line][1]{$tag} };
                                        $newline .= $sep x $tab_to_add;
                                }

                                # We replace the array with the new line
                                $oldLines[$block_line] = $newline;
                                }
                        }

                        if ( $header == NO_HEADER ) {

                                # If there are header before any of the block line,
                                # we need to remove them
                                for my $block_line ( reverse @sub_lines ) {
                                if ( ref( $oldLines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $oldLines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        splice( @oldLines, $block_line - 1, 1 );
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
                                if ( ref( $oldLines[ $sub_lines[0] - 1 ] ) ne 'ARRAY'
                                || $oldLines[ $sub_lines[0] - 1 ][0] ne 'HEADER' )
                                {
                                $need_top_header = YES;
                                }

                                # Anywhere in the block
                                for my $block_line (@sub_lines) {
                                if ( ref( $oldLines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $oldLines[ $block_line - 1 ][0] eq 'HEADER' )
                                {
                                        $oldLines[ $block_line - 1 ] = $header_line;
                                }
                                }

                                # Add a header line at the top of the block
                                if ($need_top_header) {
                                splice( @oldLines, $sub_lines[0], 0, $header_line );
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
        for (@oldLines) {
                $_ = $_->[1] if ref($_) eq 'ARRAY' && $_->[0] eq 'HEADER';
        }

        return \@oldLines;

}


1;
