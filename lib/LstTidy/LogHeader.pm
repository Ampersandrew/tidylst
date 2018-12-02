package LstTidy::LogHeader;

use strict;
use warnings;

# expand library path so we can find LstTidy modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(abs_path $0) . '/lib';

our %headings = (
   'Category CrossRef'  => "Category cross-reference problems found\n",
   'Created'            => "List of files that were created in the directory\n",
   'CrossRef'           => "Cross-reference problems found\n",
   'Type CrossRef'      => "Type cross-reference problems found\n",
   'LST'                => "Messages generated while parsing the .LST files\n",
   'Missing'            => "List of files used in a .PCC that do not exist\n",
   'PCC'                => "Messages generated while parsing the .PCC files\n",
   'System'             => "Messages generated while parsing the system files\n",
   'Unreferenced'       => "List of files that are not referenced by any .PCC files\n",
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
