package LstTidy::Line;

use strict;
use warnings;

use Mouse;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Data qw(getEntityFirstTag getEntityNameTag);
use LstTidy::Log;
use LstTidy::LogFactory qw(getLogger);
use LstTidy::Token;
use LstTidy::Options qw(getOption);

has 'columns' => (
   traits   => ['Hash'],
#   is       => 'ro',
   isa      => 'HashRef[ArrayRef[LstTidy::Token]]',
   default  => sub { {} },
   handles  => {
      column       => 'accessor',
      columns      => 'keys',
      deleteColumn => 'delete',
      hasColumn    => 'exists',
   },
);

has 'type' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'entity' => (
   is       => 'rw',
   isa      => 'Str',
   predicate => 'hasEntity',
);

has 'file' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'num' => (
   is        => 'rw',
   isa       => 'Int',
   predicate => 'hasNum',
);


=head2 appendToValue

   Append the supplied value to the end of every Token on the given column

=cut

sub appendToValue {

   my ($self, $column, $value) = @_;

   for my $token ( @{ $self->column($column) } ) {
      $token->value($token->value . $value);
   }
}


=head2 add

   This operation adds a LstTidy::Token object to the line

=cut

sub add {
   my ($self, $token) = @_;

   $self->column($token->tag, []) unless $self->column($token->tag); 

   push @{ $self->column($token->tag) }, $token;
}


=head2 columnHasSingleToken

   Returns true if the given column has a single value.

=cut

sub columnHasSingleToken {

   my ($self, $token) = @_;

   $self->hasColumn($token) && scalar $self->column($token->tag) == 1;
}



=head2 entityToken

   Return the token that holds the name of this entity

=cut

sub entityToken {
   my ($self) = @_;

   # Look up the name of the column that hold the name
   my $nameTag = getEntityFirstTag($self->lineType);
   $self->hasColumn($nameTag) && $self->column($nameTag)[0];
}


=head2 entityName

   Return the name of this entity

=cut

sub entityName {
   my ($self) = @_;

   my $token = $self->entityToken;

   # There is only a faux tag on this token, so just return the value as that
   # is the name.
   defined $token && $token->value;
}


=head2 firstColumnMatches

   Returns true if this line has the given token and the full token matches the
   given pattern.

=cut

sub firstColumnMatches {

   my ($self, $column, $pattern) = @_;

   if ($self->hasColumn($column)) {
      my @column = @{$self->column($column)};
      my $token  = $column[0];
      return $token->fullToken =~ $pattern;
   }

   return 0;   
}


=head2 getFirstTokenInColumn

   Get the token which is first in the column, returns undef if the column is
   not present in the line.

=cut

sub getFirstTokenInColumn {

   my ($self, $column) = @_;

   if ($self->hasColumn($column)) {
      my @column = @{$self->column($column)};
      return $column[0];
   }

   return undef;   
}


=head2 hasType

   This operation checks whether the line has the given type in its tokens.

=cut


sub hasType {
   my ($self, $type) = @_;

   if ($self->hasColumn('TYPE')) {
      my @types = @{ $self->column('TYPE') };
      for my $token (@types) {
         return 1 if $token->value =~ $type;
      }
   }
   return 0;
};


=head2 isType

   This opertaion checks whether the line has the given lineType.

=cut

sub isType {
   my ($self, $lineType) = @_;

   $self->type eq $lineType;
};


=head2 replaceTag

   When called with two arguments, this replaces the tag in every token in the
   column with the new tag. This creates a new column, it then deletes the
   old column.

   If only given one argument, it deletes the tokens in that column

   both versions give a report of the tokens removed from the line.

=cut

sub replaceTag {

   my ($self, $oldTag, $newTag) = @_;
   my $log = getLogger();

   for my $token ( @{ $self->column($oldTag) } ) {

      $log->warning(
         qq{Removing "} . $token->fullToken . q{".},
         $self->file,
         $self->num
      );

      if (defined $newTag) {
         $token->tag($newTag);
         $self->add($token);

         $log->warning(
            qq{Replaced with "} . $token->fullToken . q{".},
            $self->file,
            $self->num
         );
      }
   }

   $self->deleteColumn($oldTag);
}

=head2 tokenFor
   
   Create a new token that has the correct linetype, line number and file name
   to be on this line.

=cut

sub tokenFor {
   my ($self, @args) = @_;

   my $token = $self->entityToken;

   defined $token && $token->clone(@args);
}

##############################################################################

# Calculate how long this column would be if its tokens were separated with
# tabs.

sub _columnLength {
   my ($self, $key) = @_;

   my $length = 0;
   
   if ($self->hasColumn($key)) {

      my @column = @{ $self->column($key) };
      my $final  = pop @column;

      # The final item is not rounded to the tab length
      $length = defined $final ? length $final->fullRealToken : 0;

      my $tabLength = getOption('tabLength');

      # All other elements must be rounded to the next tab
      for my $token ( @column ) {
         $length += ( int( length($token->fullRealToken) / $tabLength ) + 1 ) * $tabLength;
      }
   }

   $length;
}


sub _joinWith {
   my ($self, $key, $sep) = @_;

   return "" unless $self->hasColumn($key);

   my @column = @{ $self->column($key) };

   my $final = pop @column;

   my $text;
   for my $token ( @column ) {
      $text .= $token->fullRealToken . $sep;
   }

   $text .= $final->fullRealToken;
}


=head2 _splitToken

   Split a token which has been separated by | into separate tokens.
   Mostly used to split the old style SOURCE tokens.

=cut

sub _splitToken {

   my ($line, $column) = @_;

   my @newTokens;

   for my $token (@{ $line->column($column) }) {
      if( $token->value =~ / [|] /xms ) {
         for my $tag (split '\|', $token->fullToken) {
            push @newTokens, $token->clone(fullToken => $tag);
         }

         $log->warning(
            qq{Spliting "} . $token->fullToken . q{"},
            $line->file,
            $line->num
         );

      } else {
         push @newTokens, $token;
      }
   }

   # delete the existing column and add back the tokens, if the tokens were
   # no split, this should end up where we started.
   $line->deleteColumn($column);

   for my $token (@newTokens) {
      $line->add($token);
   }
}


__PACKAGE__->meta->make_immutable;

1;
