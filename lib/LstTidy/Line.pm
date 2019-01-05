package LstTidy::Line;

use strict;
use warnings;

use Mouse;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Data;
use LstTidy::Token;
use LstTidy::Options qw(getOption);

has 'columns' => (
   traits   => ['Hash'],
#   is       => 'ro',
   isa      => 'HashRef[ArrayRef[LstTidy::Token]]',
   default  => sub { {} },
   handles  => {
      hasColumn => 'exists',
      column    => 'accessor',
   },
);

has 'lineType' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'file' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'line' => (
   is        => 'rw',
   isa       => 'Int',
   predicate => 'hasLine',
);

sub addToken {
   my ($self, $token) = @_;

   $self->column($token->tag, []) unless $self->column($token->tag); 

   push @{ $self->column($token->tag) }, $token;
}

##############################################################################

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

1;
