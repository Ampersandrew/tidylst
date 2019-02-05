package TidyLst::File;

use strict;
use warnings;

use Mouse;

has 'originalName' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'type' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'pccDirectory' => (
   is       => 'ro',
   isa      => 'Str',
   required => 1,
);

has 'inputName' => (
   is        => 'rw',
   isa       => 'Str',
   predicate => 'hasInputName',
);

has 'outputName' => (
   is        => 'rw',
   isa       => 'Str',
   predicate => 'hasOutputName',
);

has 'vendorName' => (
   is        => 'rw',
   isa       => 'Str',
   predicate => 'hasVendorName',
);

has 'isUnderInputPath' => (
   is       => 'rw',
   isa      => 'Bool',
);

has 'isMultiline' => (
   is       => 'rw',
   isa      => 'Bool',
);



# processPaths
# --------------
#
# Change the @, * and relative paths found in the .lst for the real thing.
#
# Parameters: $fileName           File name
#             $current_base_dir  Current directory

sub processPaths {
   my ($self) = @_;

   my $fileName = $self->originalName;

   # Change all the \ for / in the file name
   $fileName =~ tr{\\}{/};

   # See if the vendor path replacement is necessary
   if ($fileName =~ m{ ^[*] }xmsi) {

      # Remove the leading * and / if present
      $fileName =~ s{ ^[*] [/]? }{}xmsi;

      my $vendorFile = getOption('vendorpath') . $fileName;

      # If the vendor path replacement worked then we're done.
      if ( -e $vendorFile ) {
         $self->vendorName($vendorFile);
         $self->inputName($vendorFile);
         return 1;
      }

      # vendor path didn't work, try base path
      $fileName = '@' . $fileName;
   }

   # Potentially replace @ by the base path
   my $basePath   = getOption('basepath');
   my $mungedName = $fileName =~ s{ ^[@] [/]? }{$basePath}xmsir;

   if ($fileName eq $mungedName) {
      if ($self->pccDirectory =~ qr/\/$/) {
         $fileName = $self->pccDirectory . $fileName;
      } else {
         $fileName = $self->pccDirectory . "/${fileName}";
      }
   } else {
      $fileName = $mungedName;
   }

   # Remove the /xxx/../ for the directory
   if ($fileName =~ / [.][.] /xms ) {
      if( $fileName !~ s{ [/] [^/]+ [/]+ [.][.] [/] }{/}xmsg ) {
         die qq{Cannot deal with the .. directory in "$fileName"};
      }
   }

   # At this point $filename should have the name of the file to read.
   if ( -e $fileName ) {
      $self->inputName($fileName);
   }

   return 1;
}


1;
