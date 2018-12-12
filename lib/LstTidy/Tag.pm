package LstTidy::Tag;

use strict;
use warnings;

use Mouse;

has 'tag' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
);

has 'isNegatedPre' => (
   is     => 'rw',
   isa    => 'Bool',
);

has 'origTag' => (
   is  => 'ro',
   isa => 'Str',
);

has 'value' => (
   is        => 'rw',
   isa       => 'Maybe[Str]',
   required  => 1,
);

has 'lineType' => (
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

      # got a tagValue store it as a readonly origTag
      $args{'origTag'} = $args{'tagValue'};

      delete $args{'tagValue'};

   # no tagValue, construct an origTag
   } else {
      
      my $tag   = exists $args{'tag'} ? $args{'tag'} : q{} ;
      my $value = exists $args{'value'} ? $args{'value'} : q{};

      $args{'origTag'} = $tag . ':' . $value;
   }

   return $self->$orig(%args);
};

sub BUILD {
   my $self = shift;

   # deal with negated PRE tags, set the tag to itself because teh constructor
   # doesn't trigger the around tag sub.
   if ($self->tag =~ m/^!(pre)/i) {
      $self->tag($self->tag);
   };
};

around 'tag' => sub {
   my $orig = shift;
   my $self = shift;

   # no arguments, so this is a simple accessor
   return $self->$orig() unless @_;

   # get the new value of tag
   my $newTag = shift; 

   # modify new tag and get a boolean for if it was modified.
   my $mod = $newTag =~ s/^!(pre)/$1/i;

   # only true if new tag was a negated PRE tag
   $self->isNegatedPre($mod);

   return $self->$orig($newTag);
};

sub realTag {
   my ($self) = @_;

   my $return = defined $self->isNegatedPre && $self->isNegatedPre ? q{!} : q{};

   return  $return . $self->tag;
}

sub fullTag {
   my ($self) = @_;

   return $self->tag() . ':' . $self->value();
}

sub fullRealTag {
   my ($self) = @_;

   return $self->realTag() . ':' . $self->value();
};

1;
