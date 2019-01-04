package LstTidy::Line;

use strict;
use warnings;

use Mouse;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use LstTidy::Data;
use LstTidy::Token;

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

1;
