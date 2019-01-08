package TidyLst::Log;

use constant {
   DEBUG      => 7, # INFO message + debug message for the programmer
   INFO       => 6, # Everything including deprecations message (default)
   NOTICE     => 5, # No deprecations
   WARNING    => 4, # PCGEN will prabably not work properly
   ERROR      => 3, # PCGEN will not work properly or the script is foobar
};

# have deleted informational (who's going to type that on the command line?)
our $wlPattern = qr{^(?:d|debug|e|err|error|i|info|n|notice|w|warn|warning)}i;

use Mouse;
use Mouse::Util::TypeConstraints;
use Scalar::Util;

# Make a type that we will use to coerce a string warning level
# to an integer in the correct range.
subtype 'TidyLst::Types::WarnLevel'
   => as 'Int'
   => where { $_ >= ERROR or $_ <= DEBUG };

coerce 'TidyLst::Types::WarnLevel'
   => from 'Str'
   => via \&_coerceWarning; 

has 'header' => (
   is      => 'rw',
   isa     => 'Str',
   default => q{},
);

has 'isStartOfLog' => (
   is      => 'rw',
   isa     => 'Bool',
   default => 1,
);

has 'isOutputting' => (
   is      => 'rw',
   isa     => 'Bool',
   default => 1,
);

has 'previousFile' => (
   is      => 'rw',
   isa     => 'Str',
   default => q{},
);

has 'printHeader' => (
   is      => 'rw',
   isa     => 'Bool',
   default => 1,
);

has 'warningLevel' => (
   is       => 'rw',
   isa      => 'TidyLst::Types::WarnLevel',
   default  => NOTICE,
   required => 1,
   coerce   => 1,
);

has 'collectedWarnings' => (
   is      => 'rw',
   isa     => 'ArrayRef',
   default => sub { [] },
);

sub doOutput {
   my ($self) = shift;

   if ($self->isOutputting) {
      warn @_
   } else {
      push @{ $self->collectedWarnings }, @_
   }
}

# make sure the construction warning level is a number in range

around 'BUILDARGS' => sub {

   my $orig = shift;
   my $self = shift;

   my $foo = ref $_[0];

   if ($foo =~ /^HASH/) {

      my $wl = $_[0]->{'warningLevel'};

      if  (Scalar::Util::looks_like_number $wl) {
        if ($wl < ERROR || $wl > DEBUG) {
           # number out of range, use default
           $wl = NOTICE;
        } 
      } else {
         local $_ = $wl;

         $wl = _coerceWarning();
      };

      $_[0]->{'warningLevel'} = $wl;
   };

   return $self->$orig(@_);
};

around 'header' => sub {

   my $orig = shift;
   my $self = shift;

   return $self->$orig unless @_;

   # @_ still has values, we must be setting the value.
   my $h = shift;

   # Add a line feed before the header to separate it from the previous
   # content, unless we are at the very start of the log.
   my $header = $self->isStartOfLog() ? $h : "\n" . "${h}";

   $self->$orig($header);

   # Maske sure the header is printed next time something is logged.
   $self->printHeader(1);

   # We blank the previous file name to make sure that the file name will be
   # printed with the header.
   $self->previousFile('');
};



=head1 NAME

   TidyLst::Log - a logging package for Lst file processing

=head1 VERSION

   1.0

=head1 DESCRIPTION

   This package is used extensively for the reporting of warnings, errors, etc.
   while procdessing a set of Lst files. It is functions largely through the 
   use of the perl warn command.

   This package is based in a large part on the former Ewarn package.
   Ewarn was a start on seperating the functions of PrettyLst into
   packages with different concerns.

=cut


=head2 debug

   Log a debug message

   C<$log->debug([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut

sub debug {
   my $self = shift;
   $self->_log(DEBUG, @_);
};

=head2 info

   Log an info message

   C<$log->info([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut


sub info {    
   my $self = shift;
   $self->_log(INFO, @_);
};

=head2 notice

   Log a notice message

   C<$log->notice([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut

sub notice {  
   my $self = shift;
   $self->_log(NOTICE, @_);
};

=head2 warning

   Log a warning message

   C<$log->warning([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut


sub warning { 
   my $self = shift;
   $self->_log(WARNING, @_);
};

=head2 error

   Log an error message

   C<$log->error([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut


sub error {   
   my $self = shift;
   $self->_log(ERROR, @_);
};


=head2 _log

   This is the method that does the actual logging.

   C<$log->_log([severity], [message], [filename], [line number] )>

   The first three parameters are mandatory, the line number is optional.

   [severity] One of DEBUG INFO NOTICE WARNING or ERROR

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut

sub _log {
   my $self = shift;
   my ( $warning_level, $message, $file_name, $line_number ) = ( @_, undef );

   # Verify if warning level should be displayed
   return if ( $self->warningLevel < $warning_level );

   # Print the header if needed
   if ($self->printHeader) {
      $self->doOutput($self->header);
      $self->printHeader(0);
      $self->isStartOfLog(0);
   }

   # Windows and UNIX do not use the same charater in
   # the directory path. If we are on a Windows machine
   # we need to replace the / by a \.
   $file_name =~ tr{/}{\\} if $^O eq "MSWin32";

   # Construct the output, Add a prefix for the warning level
   my $output = {
      &DEBUG   => "DBG",
      &ERROR   => "***",
      &INFO    => "  -",
      &NOTICE  => "   ",
      &WARNING => "*=>",
   }->{$warning_level};

   # Add the line number if we have one.
   if (defined $line_number) {
      $output .= "(Line ${line_number}): "
   }

   # Add the message we were asked to output.
   $output .= $message;
   
   # Make sure there is a new-line at the end of the output.
   if ($message !~ /\n$/) {
      $output .= "\n"
   }

   # We display the file only if it is not the same are the last
   # time _log was called
   if ($file_name ne $self->previousFile) {
      $self->doOutput("$file_name\n") 
   }

   $self->doOutput($output); 

   # Set the file name of the file this message originated from
   # so that we only write each file name once.
   $self->previousFile($file_name);
};


=head2 report

   This is the method that does a simple Report for things that we don't have
   Files or line numbers for.

   C<$log->report( [message] )>

   [message] A text string describing the issue.

=cut

sub report {
   my ($self, $message) = @_;

   # Print the header if needed
   if ($self->printHeader) {
      $self->doOutput($self->header);
      $self->printHeader(0);
      $self->isStartOfLog(0);
   }
   
   # Make sure there is a new-line at the end of the output.
   if ($message !~ /\n$/) {
      $message .= "\n" 
   }

   $self->doOutput($message); 
};

# Private operation that coerces a valid string into a warning level. If passed an
# invalid value, will default to notice.

sub _coerceWarning {

   if ($_ =~ $wlPattern) {

      return { 
         d => DEBUG,
         e => ERROR,
         i => INFO,
         n => NOTICE,
         w => WARNING
      }->{ lc substr($_, 0, 1) };

   } else {

      # Default to notice
      return NOTICE;
   };
};

__PACKAGE__->meta->make_immutable;

__END__

1;
