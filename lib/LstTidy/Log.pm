package LstTidy::Log;

use Mouse;

has 'fileNamePrevious' => (
   is      => 'rw',
   isa     => 'Str',
   default => q{},
);

has 'header' => (
   is      => 'rw',
   isa     => 'Str',
   default => q{},
   writer  => \&set_header,
);

has 'isFirstError' => (
   is      => 'rw',
   isa     => 'Bool',
   default => 1,
);

has 'isStartOfLog' => (
   is      => 'rw',
   isa     => 'Bool',
   default => 1,
);

has 'warningLevel' => (
   is       => 'rw',
   isa      => 'Str',
   required => 1,
   trigger  => \&setPrefix,
);

has 'prefix' => (
   is      => 'rw',
   isa     => 'Str',
   default => q{},
);

# Private method. Called when the warning level is changed, this
# operation sets the prefix for the new warning level.

sub setPrefix {

   my ($self, $level, $old_level) = @_;

   my $prefix = {
      7   => "DBG",   # DEBUG
      6   => "  -",   # INFO
      5   => "   ",   # NOTICE
      4   => "*=>",   # WARNING
      3   => "***",   # ERROR
   }->{$level};

   $self->prefix($prefix);
}

=head1 NAME

   LstTidy::Log - a logging package for Lst file processing

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

=head2 set_header

   Set the header for the error message.

   This also ensures the header is displayed on the first log call after
   setting this value.

=cut

sub set_header
{
   my ($self, $h) = @_;

   # Add a line feed before the header to separate it from the previous
   # content, unless we are at the very start of the log.
   my $header = $self->isStartOfLog() ? $h : "\n${h}";

   $self->header($header);
   $self->isFirstError(1);

   # We blank the previous file name to make sure that the file name will be
   # printed with the first message after the header.
   $self->fileNamePrevious('');
}

=head2 debug

   Log a debug message

   C<$logger->debug([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut

sub debug {
   my $self = shift;
   $self->log(7, @_);
};

=head2 info

   Log an info message

   C<$logger->info([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut


sub info {    
   my $self = shift;
   $self->log(6, @_);
};

=head2 notice

   Log a notice message

   C<$logger->notice([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut

sub notice {  
   my $self = shift;
   $self->log(5, @_);
};

=head2 warning

   Log a warning message

   C<$logger->warning([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut


sub warning { 
   my $self = shift;
   $self->log(4, @_);
};

=head2 error

   Log an error message

   C<$logger->error([message], [filename], [line number] )>

   The first two parameters are mandatory, the line number is optional.

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut


sub error {   
   my $self = shift;
   $self->log(3, @_);
};


=head2 _log

   This is the method that does the actual logging.

   C<$logger->_log([severity], [message], [filename], [line number] )>

   The first three parameters are mandatory, the line number is optional.

   [severity] One of DEBUG INFO NOTICE WARNING or ERROR

   [message] A text string describing the issue.

   [filename] The name of the file containing the problem.

   [line number] An optional line number where the issue is located.

=cut

sub _log
{
   my $self = shift;
   my ( $warning_level, $message, $file_name, $line_number ) = ( @_, undef );

   # Verify if warning level should be displayed
   return if ( $self->warningLevel() < $warning_level );

   # Print the header if needed
   if ($self->isFirstError()) {
      warn $self->header();
      $self->isFirstError(0);
      $self->isStartOfLog(0);
   }

   # Windows and UNIX do not use the same charater in
   # the directory path. If we are on a Windows machine
   # we need to replace the / by a \.
   $file_name =~ tr{/}{\\} if $^O eq "MSWin32";

   my $output = $self->prefix();

   # Construct the output, add the line number if we have one.
   # so, make sure there is a new-line at the end of the output.
   $output .= "(Line ${line_number}): " if defined $line_number;
   $output .= $message;

   $output .= "\n" unless $message =~ /\n$/;

   # We display the file only if it is not the same are the last
   # time _log was called
   warn "$file_name\n" if $file_name ne $self->fileNamePrevious();

   warn $output; 

   # Set the file name of the file this message originated from
   # so that we only write each file name once.
   $self->fileNamePrevious($file_name);
}

__PACKAGE__->meta->make_immutable;

__END__

1;
