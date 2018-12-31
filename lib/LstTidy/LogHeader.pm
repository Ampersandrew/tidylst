package LstTidy::LogHeader;

use strict;
use warnings;

our %headings = (
   'Bonus and PRE'      => "List of BONUS and PRExxx tags by linetype\n",
   'Category CrossRef'  => "Category cross-reference problems found\n",
   'Created'            => "List of files that were created in the directory\n",
   'CrossRef'           => "Cross-reference problems found\n",
   'Invalid Tags'       => "Invalid tags found\n",
   'LST'                => "Messages generated while parsing the .LST files\n",
   'Missing Header'     => "List of TAGs without a defined header\n",
   'Missing LST'        => "List of files used in a .PCC that do not exist\n",
   'PCC'                => "Messages generated while parsing the .PCC files\n",
   'System'             => "Messages generated while parsing the system files\n",
   'Type CrossRef'      => "Type cross-reference problems found\n",
   'Unreferenced'       => "List of files that are not referenced by any .PCC files\n",
   'Valid Tags'         => "Valid tags found\n",
);


=head2 get

   This operation constructs a heading for the logging program.

=cut

sub get {
   my ($headerRef, $path) = @_;

   my $header = "================================================================\n";

   if (exists $headings{$headerRef}) {
      $header .= $headings{$headerRef};
   }

   if (defined $path) {
      $header .= $path . "\n";
   }

   $header   .= "----------------------------------------------------------------\n";
}


1;
