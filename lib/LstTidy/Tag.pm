package LstTidy::Tag;

use strict;
use warnings;

use Mouse;

has 'tag' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'value' => (
   is        => 'rw',
   isa       => 'Maybe[Str]',
   required  => 1,
);

has 'linetype' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'file' => (
   is      => 'rw',
   isa     => 'Str',
   required => 1,
);

has 'line' => (
   is        => 'rw',
   isa       => 'Int',
   predicate => 'hasLine',
);

around 'BUILDARGS' => sub {

   my $orig = shift;
   my $self = shift;

   my %args = ( @_ > 1 ) ? @_ : %{ $_[0] } ;

   if ( exists $args{'tagValue'} ) {
      @args{'tag', 'value'} = split ':', $args{'tagValue'}, 2;
      delete $args{'tagValue'};
   }

   return $self->$orig(%args);
};

1;
