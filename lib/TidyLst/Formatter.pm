package TidyLst::Formatter;

use strict;
use warnings;

use Mouse;

# expand library path so we can find TidyLst modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Data qw(getOrderForLineType);

has 'columns' => (
   traits   => ['Hash'],
#   is       => 'ro',
   isa      => 'HashRef[Int]',
   default  => sub { {} },
   handles  => {
      column       => 'accessor',
      columns      => 'keys',
      deleteColumn => 'delete',
      hasColumn    => 'exists',
      noTokens     => 'is_empty',
   },
);

has 'type' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);


=head2 adjustLengthsForHeaders

   For each column inthis object, it adjusts the value maximum of its current
   value or the length of the header for that column.

=cut

sub adjustLengthsForHeaders {

   my ($self) = @_;

   for my $col (@{$self->columns}) {

      my $len = length getHeader($col, $self->type);

      if($self->column($col) < $len) {
         $self->column($col, $len)
      }
   }
}


=head2 adjustLengths

   Takes a TidyLst::Line and for each column in the Line, it adjusts the value
   of the column in this object to the maximum of this object's current value or
   the $line's column length.

   After this operation has run, columns has an entry for each column that has
   been seen on any line processed using adjustLengths. The value of the column is
   the maximum length of that column in all the lines processed.

=cut

sub adjustLengths {

   my ($self, $line) = @_;

   for my $col (@{$line->columns}) {

      my $len = $line->columnLength($col);

      if ($self->hasColumn($col)) {
         if($self->column($col) < $len) {
            $self->column($col, $len)
         }
      } else {
         $self->column($col, $len)
      }
   }
}


=head2 constructHeaderLine

   Make a header line for the columns of this group of lines, with each of the
   columns in this object present in the header and occupying the amount of space
   specified in the column attribute of this object.

=cut

sub constructHeaderLine {
   my ($self, $tabLength) = @_;

   my %columns = map { $_ => 1 } $self->columns;
   my $order   = getOrderForLineType($self->type);
   my $headerLine;

   # Do the defined columns first
   for my $col (@{$order}) {

      if ($self->hascolumn($col)) {
         # get rid of the column so we can put the left overs at the end
         delete $columns($col);

         # Make sure there is a tab between the widest value in this column and
         # the next column (if it happens to be a multiple of tablength).
         my $columnLength = $self->column($col) + $tabLength;

         # calculate the maximum length of this column, as a whole number of tabs
         my $max = _roundUpToTabLength($columnLength, $tabLength);
         
         my $header   = getHeader($col, $self->type);
         my $leftover = _roundUpToTabLength($max - length $header, $tabLength);
         my $toAdd    = int($leftover / $tabLength);

         $headerLine .= $header . "\t" x $toAdd;
      }
   }

   # Add columns found in this group of lines that aren't in the master order
   for my $col (sort keys %columns) {

      # Make sure there is a tab between the widest value in this column and
      # the next column (if it happens to be a multiple of tablength).
      my $columnLength = $self->column($col) + $tabLength;

      # calculate the maximum length of this column, as a whole number of tabs
      my $max = _roundUpToTabLength($columnLength, $tabLength);

      my $header   = getHeader($col, $self->type);
      my $leftover = _roundUpToTabLength($max - length $header, $tabLength);
      my $toAdd    = int ($leftover / $tabLength);

      $headerLine .= $header . "\t" x $toAdd;
   }

   # Remove the extra tabs at the end
   $headerLine =~ s/"\t"+$//;

   $headerLine;
}


=head2 constructLine

   Make a text line for the columns in this Line. Each of the columns present
   in this Formatter will be present and occupying the amount of space
   specified in the column attribute of this Formatter object.  Space will be
   left for columns not present in this Line.

=cut

sub constructLine {
   my ($self, $line, $tabLength) = @_;

   my %columns = map { $_ => 1 } $self->columns;
   my $order   = getOrderForLineType($self->type);
   my $fileLine;

   # Do the defined columns first
   for my $col (@{$order}) {

      if ($self->hascolumn($col)) {
         # get rid of the column so we can put the left overs at the end
         delete $columns($col);

         # Make sure there is a tab between the widest value in this column and
         # the next column (if it happens to be a multiple of tablength).
         my $columnLength = $self->column($col) + $tabLength;

         # calculate the maximum length of this column, as a whole number of tabs
         my $max = _roundUpToTabLength($columnLength, $tabLength);
         
         my $column   = $line->joinwith($col, "\t");
         my $leftover = _roundUpToTabLength($max - $line->columnLength($col), $tabLength);
         my $toAdd    = int($leftover / $tabLength);

         $fileLine .= $column . "\t" x $toAdd;
      }
   }

   # Add columns found in this group of lines that aren't in the master order
   for my $col (sort keys %columns) {

      # Make sure there is a tab between the widest value in this column and
      # the next column (if it happens to be a multiple of tablength).
      my $columnLength = $self->column($col) + $tabLength;

      # calculate the maximum length of this column, as a whole number of tabs
      my $max = _roundUpToTabLength($columnLength, $tabLength);

      my $column   = $line->joinwith($col, "\t");
      my $leftover = _roundUpToTabLength($max - $line->columnLength($col), $tabLength);
      my $toAdd    = int ($leftover / $tabLength);

      $fileLine .= $column . "\t" x $toAdd;
   }

   # Remove the extra tabs at the end
   $fileLine =~ s/"\t"+$//;

   $fileLine;
}


=head2 _roundUpToTabLength

   Round this length to the smallest multiple of tabLength that can hold it.

=cut

sub roundUpToTabLength {
   my ($length, $tabLength) = @_;

   int (($length + $tabLength - 1) / $tabLength) * $tabLength;
} 

1;
