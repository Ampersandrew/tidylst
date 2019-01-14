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
   my @newLines;

   my $tabLength = getOption('tabLength');

   CORE_LINE:
   for ( my $index = 0; $index < @oldLines; $index++ ) {

      if (! ref $oldLines[$index] eq 'ARRAY') {
         die 'Oops not an array';
      }

      my $lineRef = $oldLines[$index];
      my $line    = $lineRef->[LINEOBJECT];

      if (!defined $line || ref $line ne 'TidyLst::Line') {
         die 'Oops not a line object';
      }

      # headers, comments and blank lines
      if ($line->type =~ $TidyLst::Convert::tokenlessRegex) {
         push @newLines, $line;
         next CORE_LINE
      }

      my $newline  = "";
      my $lastLine = $newLines[-1];

      if ($line->mode == SINGLE || $line->format == LINE) {

         # if the previous line was a header, remove it.
         if ($lastLine->type eq 'HEADER') {
            pop @newLines;
         }

         my $formatter = TidyLst::Formatter->new(type => $line->type);
         $formatter->adjustLengths($line);

         if ($line->header == NO_HEADER) {

            # Rewrite the unsplit version of this line
            $line->unsplit($formatter->constructLine($line, $tabLength));

            push @newLines, $line;
            next CORE_LINE

         } elsif ($line->header == LINE_HEADER) {

            # Add an empty line in front of the header unless there is already
            # one or the previous line matches the line entity.

            if ($lastLine->type ne 'BLANK' && $lastLine->entityName ne $line->entityName) {
               my $blankLine = $line->cloneNoTokens;
               $blankLine->type('BLANK');
               push @newLines, $blankLine;
            }

            $formatter->adjustLengthsForHeaders();

            my $headerLine = $line->cloneNoTokens;
            $headerLine->type('HEADER');
            $headerLine->unsplit($formatter->constructHeaderLine($tabLength));
            push @newLines, $headerLine;

            $line->unsplit($formatter->constructLine($line, $tabLength));
            push @newLines, $line;

         } else {

            # Invalid option
            die qq(Invalid \%TidyLst::Parse::parseControl options: )
            . $fileType . q(:)
            . $line->type . q(:)
            . $line->mode . q(:)
            . $line->header;
         }


      # Every file type that has lines of mode MAIN and format BLOCK, only has
      # linetypes of mode MAIN and format BLOCK.  This means that in these
      # files, the only way to end a block is with a change of linetype or a
      # block header.
      #
      # Some files have a mixture of MAIN and SUB, but in all of these, the
      # lines of mode MAIN are format LINE.


      } elsif ( $line->mode == MAIN ) {

         # No such thing as a Main line with FIRST_COLUMN, only LINE or BLOCK
         if ( $line->format != BLOCK ) {

            die qq(Invalid \%TidyLst::Parse::parseControl format: )
            . $fileType . q(:)
            . $line->type . q(:)
            . $line->mode . q(:)
            . $line->header;

         } else {

            my $formatter = TidyLst::Formatter->new(type => $line->type);

            # All the main lines must be found up until a different main line
            # type or a ###Block comment.

            my $lastInBlock = $index;

            BLOCK_LINE:
            for ( ; $lastInBlock < @oldLines; $lastInBlock++) {

               my $this = $oldLines[$lastInBlock];

               # If a '###Block' comment is found or the line_type changes, we
               # are out of the block
               if ($this->type eq 'BLOCK_COMMENT' ||
                  ($this->mode == MAIN && $this->type ne $line->type)) {

                  # type has changed, don't include this line in the block
                  $lastInBlock--;
                  last BLOCK_LINE
               }

               # Skip the lines already dealt with i.e. headers, comments and
               # blank lines (this Regex also finds BLOCK_COMMENTS, but they've
               # already been dealt with.
               if ($this->type =~ $TidyLst::Convert::tokenlessRegex) {
                  next BLOCK_LINE
               }

               # This line has tokens
               if ($this->mode == MAIN) {
                  $formatter->adjustLengths($this);
               }
            }


            # If the first line of this block has some kind of header, make a
            # header line for it
            if ($line->header != NO_HEADER) {
               $formatter->adjustLengthsForHeaders();

               my $headerLine = $line->cloneNoTokens;
               $headerLine->type('HEADER');
               $headerLine->unsplit($formatter->constructHeaderLine($tabLength));
               push @newLines, $headerLine;
            }

            BLOCK_LINE:
            for my $inx ($index .. $lastInBlock) {

               # When $inx is 0, previous is the last line of the file. This is
               # unlikely to create problems since neither the first nor the
               # last line will be a header. Previous is only used to decide
               # whether to add a header before $this.
               my $this = $oldLines[$inx];

               # If this was identified as a header line earlier, add a copy of
               # the header line we made earlier
               if ($this->type eq 'HEADER' && $line->header != NO_HEADER) {

                  # This code disallows multiple contiguous header lines
                  my $previous = $oldLines[$inx - 1];

                  if ($previous->type ne 'HEADER') {
                     my $headerLine = $this->cloneNoTokens;
                     $headerLine->type('HEADER');
                     $headerLine->unsplit($formatter->constructHeaderLine($tabLength));
                     push @newLines, $headerLine;
                  }

                  next BLOCK_LINE;
               }

               # At this point Comments, block comments and blanks, push them
               # unmodified.
               if ($this->type =~ $TidyLst::Convert::tokenlessRegex) {
                  push @newLines, $this;
                  next BLOCK_LINE;
               }

               # reformat the unsplit version of this line and push it onto new
               # lines
               $this->unsplit($formatter->constructLine($this, $tabLength));
               push @newLines, $this;
            }
         }

      } elsif ( $line->mode == SUB ) {

         if ( $line->format == LINE ) {

            die "SUB:LINE not implemented yet";

         } elsif ( $line->format == BLOCK || $line->format == FIRST_COLUMN ) {

            my $formatter = TidyLst::Formatter->new(type => $line->type);

            # All the main lines must be found up until a different main line
            # type or a ###Block comment.

            my $lastInBlock = $index;

            BLOCK_LINE:
            for ( ; $lastInBlock < @oldLines; $lastInBlock++) {

               my $this = $oldLines[$lastInBlock];

               # If a Main line or a '###Block' comment is found, we are out of
               # the block
               if ($this->type eq 'BLOCK_COMMENT' || $this->mode == MAIN) {

                  # type has changed, don't include this line in the block
                  $lastInBlock--;
                  last BLOCK_LINE
               }

               # Skip the lines already dealt with i.e. headers, comments and
               # blank lines (this Regex also finds BLOCK_COMMENTS, but they've
               # already been dealt with.
               if ($this->type =~ $TidyLst::Convert::tokenlessRegex) {
                  next BLOCK_LINE
               }

               # This line has tokens
               if ($this->mode == MAIN) {
                  $formatter->adjustLengths($this);
               }
            }






















            #####################################
            # Need to find all the file in the SUB BLOCK i.e. same line type
            # within two MAIN lines.
            # If we encounter a ###Block comment, that's the end of the block

            # Each of the block lines must be reformated
            if ( $line->format == BLOCK ) {
               for my $block_line (@sub_lines) {
                  my $newline;

                  for my $tag (@col_order) {
                     my $col_max_length
                     = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );

                     # Is the tag present in this line?
                     if ( exists $oldLines[$block_line][LINETOKENS]{$tag} ) {
                        my $curent_length = mylength( $oldLines[$block_line][LINETOKENS]{$tag} );

                        my $tab_to_add
                        = int( ( $col_max_length - $curent_length ) / $tablength )
                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                        $newline .= join $sep, @{ $oldLines[$block_line][LINETOKENS]{$tag} };
                        $newline .= $sep x $tab_to_add;

                     } else {

                        # We pad with tabs
                        $newline .= $sep x ( $col_max_length / $tablength );
                     }
                  }

                  # We replace the array with the new line
                  $oldLines[$block_line] = $newline;
               }

            } else {

               # $line->format == FIRST_COLUMN

               for my $block_line (@sub_lines) {

                  my $newline;
                  my $first_column = YES;
                  my $tab_to_add;

                  TAG:
                  for my $tag (@col_order) {

                     # Is the tag present in this line?
                     next TAG if !exists $oldLines[$block_line][LINETOKENS]{$tag};

                     if ($first_column) {
                        my $col_max_length
                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                        my $curent_length = mylength( $oldLines[$block_line][LINETOKENS]{$tag} );

                        $tab_to_add
                        = int( ( $col_max_length - $curent_length ) / $tablength )
                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );

                        # It's no longer the first column
                        $first_column = NO;

                     } else {
                        $tab_to_add = 1;
                     }

                     $newline .= join $sep, @{ $oldLines[$block_line][LINETOKENS]{$tag} };
                     $newline .= $sep x $tab_to_add;
                  }

                  # We replace the array with the new line
                  $oldLines[$block_line] = $newline;
               }
            }

                        if ( $line->header == NO_HEADER ) {

                                # If there are header before any of the block line,
                                # we need to remove them
                                for my $block_line ( reverse @sub_lines ) {
                                if ( ref( $oldLines[ $block_line - 1 ] ) eq 'ARRAY'
                                        && $oldLines[ $block_line - 1 ][LINETYPE] eq 'HEADER' )
                                {
                                        splice( @oldLines, $block_line - 1, 1 );
                                        $index--;
                                }
                                }
                        } elsif ( $line->header == LINE_HEADER ) {
                                die "SUB:BLOCK:LINE_HEADER not implemented yet";
                        } elsif ( $line->header == BLOCK_HEADER ) {

                                # We must add the header line at the top of the block
                                # and anywhere else we find them whitin the block.

                                my $header_line;
                                for my $tag (@col_order) {

                                # Round the col_length up to the next tab
                                my $col_max_length
                                        = $tablength * ( int( $col_length{$tag} / $tablength ) + 1 );
                                my $current_header = getHeader( $tag, $sub_linetype );
                                my $current_length = mylength($current_header);
                                my $tab_to_add  = int( ( $col_max_length - $current_length ) / $tablength )
                                        + ( ( $col_max_length - $curent_length ) % $tablength ? 1 : 0 );
                                $header_line .= $current_header . $sep x $tab_to_add;
                                }

                                # Before the top of the block
                                my $need_top_header = NO;
                                if ( ref( $oldLines[ $sub_lines[0] - 1 ] ) ne 'ARRAY'
                                || $oldLines[ $sub_lines[0] - 1 ][LINETYPE] ne 'HEADER' )
                                {
                                $need_top_header = YES;
                                }

                                # Anywhere in the block
                                for my $block_line (@sub_lines) {
                                   if ( ref( $oldLines[ $block_line - 1 ] ) eq 'ARRAY'
                                      && $oldLines[ $block_line - 1 ][LINETYPE] eq 'HEADER' ) {

                                      $oldLines[ $block_line - 1 ] = $header_line;
                                   }
                                }

                                # Add a header line at the top of the block
                                if ($need_top_header) {
                                   splice( @oldLines, $sub_lines[0], 0, $header_line );
                                   $index++;
                                }

                        } else {
                                die qq(Invalid \%TidyLst::Parse::parseControl )
                                . $line->type . q(:)
                                . $line->mode . q(:)
                                . $line->format . q(:)
                                . $line->header;
                        }

                } else {
                        die qq(Invalid \%TidyLst::Parse::parseControl )
                        . $line->type . q(:)
                        . $line->mode . q(:)
                        . $line->format . q(:)
                        . $line->header;
                }

             } else {
                die qq(Invalid \%TidyLst::Parse::parseControl mode: )
                . $fileType . q(:)
                . $line->type . q(:)
                . $line->mode;
             }
        }

        # If there are header lines remaining, we keep the old value
        for (@oldLines) {
           $_ = $_->[LINETOKENS] if ref($_) eq 'ARRAY' && $_->[LINETYPE] eq 'HEADER';
        }

        return \@oldLines;
}


1;
