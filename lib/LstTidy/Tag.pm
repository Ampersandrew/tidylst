package LstTidy::Tag;

use strict;
use warnings;

use Mouse;

has 'id' => (
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

has 'noMoreErrors' => (
   is     => 'rw',
   isa    => 'Bool',
);

around 'BUILDARGS' => sub {

   my $orig = shift;
   my $self = shift;

   my %args = ( @_ > 1 ) ? @_ : %{ $_[0] } ;

   if ( exists $args{'fullTag'} ) {
      @args{'id', 'value'} = split ':', $args{'fullTag'}, 2;

      # got a fullTag store it as a readonly origTag
      $args{'origTag'} = $args{'fullTag'};

      delete $args{'fullTag'};

   # no fullTag, construct an origTag
   } else {
      
      my $id   = exists $args{'id'} ? $args{'id'} : q{} ;
      my $value = exists $args{'value'} ? $args{'value'} : q{};

      $args{'origTag'} = $id . ':' . $value;
   }

   return $self->$orig(%args);
};

sub BUILD {
   my $self = shift;

   # deal with negated PRE tags, set the id to itself because teh constructor
   # doesn't trigger the around id sub.
   if ($self->id =~ m/^!(pre)/i) {
      $self->id($self->id);
   };
};

around 'id' => sub {
   my $orig = shift;
   my $self = shift;

   # no arguments, so this is a simple accessor
   return $self->$orig() unless @_;

   # get the new value of id
   my $newId = shift; 

   # modify new id and get a boolean for if it was modified.
   my $mod = $newId =~ s/^!(pre)/$1/i;

   # only true if new id was a negated PRE tag
   $self->isNegatedPre($mod);

   return $self->$orig($newId);
};

sub realId {
   my ($self) = @_;

   my $return = defined $self->isNegatedPre && $self->isNegatedPre ? q{!} : q{};

   return  $return . $self->id;
}

sub fullTag {
   my ($self) = @_;

   my $sep = $self->id =~ m/:/ ? q{} : q{:};

   return $self->id() . $sep . $self->value();
}

sub fullRealTag {
   my ($self) = @_;

   my $sep = $self->id =~ m/:/ ? q{} : q{:};

   return $self->realId() . $sep . $self->value();
}

sub clone {
   my ($self, %params) = @_;

   my $newTag = $self->meta->clone_object($self, %params);

   if (exists $params{id}) {
      $newTag->id($params{id}) ;
   }

   return $newTag;
}

__PACKAGE__->meta->make_immutable;

1;
