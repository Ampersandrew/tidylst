package LstTidy::Report;

use strict;
use warnings;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

# predeclare this so we can call it without & or trailing () like a builtin
sub report_tag_sort;

# Will hold the number of each tag found (by linetype)
my %count_tags;

sub incCountValidTags {
   my ($lineType, $tag) = @_;

   $count_tags{"Valid"}{"Total"}{$tag}++;
   $count_tags{"Valid"}{$lineType}{$tag}++;
}

sub incCountInvalidTags {
   my ($lineType, $tag) = @_;

   $count_tags{"Invalid"}{"Total"}{$tag}++;
   $count_tags{"Invalid"}{$lineType}{$tag}++;
}

=head2 foundInvalidTags

   Returns true if any invalid tags were found while processing the lst files.

=cut

sub foundInvalidTags {
   return exists $count_tags{"Invalid"};
}

=head2 reportValid
   
   Print a report for the number of tags found.
   
=cut

sub reportValid {

   print STDERR "\n================================================================\n";
   print STDERR "Valid tags found\n";
   print STDERR "----------------------------------------------------------------\n";

   my $first = 1;
   REPORT_LINE_TYPE:
   for my $line_type ( sort keys %{ $count_tags{"Valid"} } ) {
      next REPORT_LINE_TYPE if $line_type eq "Total";

      print STDERR "\n" unless $first;
      print STDERR "Line Type: $line_type\n";

      for my $tag ( sort report_tag_sort keys %{ $count_tags{"Valid"}{$line_type} } ) {

         my $tagdisplay = $tag;
         $tagdisplay .= "*" if LstTidy::Reformat::isValidMultiTag($line_type, $tag);
         my $line = "    $tagdisplay";
         $line .= ( " " x ( 26 - length($tagdisplay) ) ) . $count_tags{"Valid"}{$line_type}{$tag};

         print STDERR "$line\n";
      }

      $first = 0;
   }

   print STDERR "\nTotal:\n";

   for my $tag ( sort report_tag_sort keys %{ $count_tags{"Valid"}{"Total"} } ) {

      my $line = "    $tag";
      $line .= ( " " x ( 26 - length($tag) ) ) . $count_tags{"Valid"}{"Total"}{$tag};

      print STDERR "$line\n";
   }
}




=head2 reportInvalid


=cut


sub reportInvalid {

   print STDERR "\n================================================================\n";
   print STDERR "Invalid tags found\n";
   print STDERR "----------------------------------------------------------------\n";

   my $first = 1;
   INVALID_LINE_TYPE:
   for my $linetype ( sort keys %{ $count_tags{"Invalid"} } ) {

      next INVALID_LINE_TYPE if $linetype eq "Total";

      print STDERR "\n" unless $first;
      print STDERR "Line Type: $linetype\n";

      for my $tag ( sort report_tag_sort keys %{ $count_tags{"Invalid"}{$linetype} } ) {

         my $line = "    $tag";
         $line .= ( " " x ( 26 - length($tag) ) ) . $count_tags{"Invalid"}{$linetype}{$tag};
         print STDERR "$line\n";
      }

      $first = 0;
   }

   print STDERR "\nTotal:\n";

   for my $tag ( sort report_tag_sort keys %{ $count_tags{"Invalid"}{"Total"} } ) {

      my $line = "    $tag";
      $line .= ( " " x ( 26 - length($tag) ) ) . $count_tags{"Invalid"}{"Total"}{$tag};
      print STDERR "$line\n";

   }
}



=head2 report_tag_sort

   Sort used for the tag when reporting them.

   Basicaly, it's a normal ASCII sort except that the ! are removed when found
   (the PRExxx and !PRExxx are sorted one after the other).

=cut

sub report_tag_sort {
   my ( $left, $right ) = ( $a, $b );      # We need a copy in order to modify

   # Remove the !. $not_xxx contains 1 if there was a !, otherwise
   # it contains 0.
   my $not_left  = $left  =~ s{^!}{}xms;
   my $not_right = $right =~ s{^!}{}xms;

   $left cmp $right || $not_left <=> $not_right;
}

1;
