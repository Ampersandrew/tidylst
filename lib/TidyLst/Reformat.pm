package TidyLst::Reformat;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   reformatFile
   );

use YAML;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Data qw(
   BLOCK FIRST_COLUMN LINE LINE_HEADER MAIN NO_HEADER SINGLE SUB
   );
use TidyLst::Formatter;
use TidyLst::Options qw(getOption);

=head2 reformatFile

   Reformat the lines of this file for writing.

=cut

sub reformatFile {

   my ($fileType, $lines) = @_;

   my @oldLines = @{ $lines };
   my @newLines;

   my $lastInBlock;
   my $tabLength = getOption('tabLength');

   CORE_LINE:
   for ( my $index = 0; $index < @oldLines; $index++ ) {

      my $line = $oldLines[$index];

      if (ref $line ne 'TidyLst::Line') {
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
         if (defined $lastLine && $lastLine->type eq 'HEADER') {
            pop @newLines;
            $lastLine = $newLines[-1];
         }

         my $formatter = TidyLst::Formatter->new(
            type      => $line->type,
            tabLength => $tabLength,
         );
         $formatter->adjustLengths($line);

         if ($line->header == NO_HEADER) {

            # Rewrite the unsplit version of this line
            $line->unsplit($formatter->constructLine($line));

            push @newLines, $line;
            next CORE_LINE

         } elsif ($line->header == LINE_HEADER) {

            # Add an empty line in front of the header unless there is already
            # one or the previous line matches the line entity.
            
            my $addBlank = 
               ((defined $lastLine && $lastLine->type !~ $TidyLst::Convert::tokenlessRegex) 
                  && ($lastLine->entityName ne $line->entityName))
               || (defined $lastLine && $lastLine->type ne 'BLANK');

            if ($addBlank) {
               my $blankLine = $line->cloneNoTokens;
               $blankLine->type('BLANK');
               push @newLines, $blankLine;
            }

            $formatter->adjustLengthsForHeaders();

            my $headerLine = $line->cloneNoTokens;
            $headerLine->type('HEADER');
            $headerLine->unsplit($formatter->constructHeaderLine());
            push @newLines, $headerLine;

            $line->unsplit($formatter->constructLine($line));
            push @newLines, $line;
            next CORE_LINE

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

            my $formatter = TidyLst::Formatter->new(
               type      => $line->type,
               tabLength => $tabLength,
            );

            # All the main lines must be found up until a different main line
            # type or a ###Block comment.

            $lastInBlock = $index;

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

            if ($lastInBlock > $#oldLines) {
               $lastInBlock = $#oldLines;
            }

            # If the first line of this block has some kind of header, make a
            # header line for it
            if ($line->header != NO_HEADER) {
               $formatter->adjustLengthsForHeaders();

               my $headerLine = $line->cloneNoTokens;
               $headerLine->type('HEADER');
               $headerLine->unsplit($formatter->constructHeaderLine());
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
                     $headerLine->unsplit($formatter->constructHeaderLine());
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
               $this->unsplit($formatter->constructLine($this));
               push @newLines, $this;
            }
         }

      } elsif ( $line->mode == SUB ) {

         if ($line->header != NO_HEADER) {
            die "SUB must not have a header";
         }

         if ( $line->format == BLOCK || $line->format == FIRST_COLUMN ) {

            my $formatter = TidyLst::Formatter->new(
               type      => $line->type,
               tabLength => $tabLength,
            );

            # All the sub lines must be found up until a different sub line
            # type, a main line type, or a ###Block comment is encountered.

            $lastInBlock = $index;

            BLOCK_LINE:
            for ( ; $lastInBlock < @oldLines; $lastInBlock++) {

               my $this = $oldLines[$lastInBlock];

               if ($this->type eq 'BLOCK_COMMENT') {

                  # Don't include this line in the block
                  $lastInBlock--;
                  last BLOCK_LINE
               }

               # Skip the lines already dealt with i.e. headers, comments and
               # blank lines (this Regex also finds BLOCK_COMMENTS, but they've
               # already been dealt with.
               if ($this->type =~ $TidyLst::Convert::tokenlessRegex) {
                  next BLOCK_LINE
               }

               if ($this->type ne $line->type) {

                  # Don't include this line in the block
                  $lastInBlock--;
                  last BLOCK_LINE
               }

               # This line has tokens
               $formatter->adjustLengths($this);
            }

            if ($lastInBlock > $#oldLines) {
               $lastInBlock = $#oldLines;
            }

            if ( $line->format == BLOCK) {

               BLOCK_LINE:
               for my $inx ($index .. $lastInBlock) {

                  # When $inx is 0, previous is the last line of the file. This is
                  # unlikely to create problems since neither the first nor the
                  # last line will be a header. Previous is only used to decide
                  # whether to add a header before $this.
                  my $this = $oldLines[$inx];

                  # At this point Comments, block comments and blanks, push them
                  # unmodified.
                  if ($this->type =~ $TidyLst::Convert::tokenlessRegex) {
                     push @newLines, $this;
                     next BLOCK_LINE;
                  }

                  # reformat the unsplit version of this line and push it onto new
                  # lines
                  $this->unsplit($formatter->constructLine($this));
                  push @newLines, $this;
               }

            } else {

               BLOCK_LINE:
               for my $inx ($index .. $lastInBlock) {

                  # When $inx is 0, previous is the last line of the file. This is
                  # unlikely to create problems since neither the first nor the
                  # last line will be a header. Previous is only used to decide
                  # whether to add a header before $this.
                  my $this = $oldLines[$inx];

                  # At this point Comments, block comments and blanks, push them
                  # unmodified.
                  if ($this->type =~ $TidyLst::Convert::tokenlessRegex) {
                     push @newLines, $this;
                     next BLOCK_LINE;
                  }

                  # reformat the unsplit version of this line and push it onto new
                  # lines
                  $this->unsplit($formatter->constructFirstColumnLine($this));
                  push @newLines, $this;
               }
            }
         }
      }

      if (defined $lastInBlock) {
         $index = $lastInBlock;
      }

   }

   my @lines = map {$_->unsplit} @newLines;

   return \@lines;
}


1;
