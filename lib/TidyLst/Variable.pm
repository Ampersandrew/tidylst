package TidyLst::Variable;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
   oldExtractVariables
   parseJepFormula
   );

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0);

use TidyLst::Log;
use TidyLst::LogFactory qw(getLogger);

use TidyLst::Data qw(registerXCheck);


# List of keywords Jep functions names. The fourth and fifth rows are for
# functions defined by the PCGen libraries that do not exists in
# the standard Jep library.
my %isJepFunction = map { $_ => 1 } qw(
   sin     cos     tan     asin    acos    atan    atan2   sinh
   cosh    tanh    asinh   acosh   atanh   ln      log     exp
   abs     rand    mod     sqrt    sum     if      str

   charbonusto ceil    cl      classlevel      count   floor
   min         max     roll    skillinfo       var     mastervar
   APPLIEDAS
);

# Definition of a valid Jep identifiers. Note that all functions are
# identifiers followed by a parentesis.
my $isIdentRegex = qr{ [a-z_][a-z_0-9]* }xmsi;

# Valid Jep operators
my $isOperatorsText = join( '|', map { quotemeta } (
      '^', '%',  '/',  '*',  '+',  '-', '<=', '>=', '<', '>', '!=', '==', '&&', '||', '=',  '!', '.',
   )
);

my $isOperatorRegex = qr{ $isOperatorsText }xms;

my $isNumberRegex = qr{ (?: \d+ (?: [.] \d* )? ) | (?: [.] \d+ ) }xms;

=head2 oldExtractVariables

   The prejep variable parser. This is used by the jep parser and also when the
   jep option is turned off.

=cut

sub oldExtractVariables {

   my ( $formula, $tag, $file, $line ) = @_;

   return () unless $formula;

   # Will hold the result values
   my @variable_names = ();

   # Get the logger singleton
   my $log = getLogger();

   # We remove the COUNT[xxx] from the formulas
   while ( $formula =~ s/(COUNT\[[^]]*\])//g ) {
      push @variable_names, $1;
   }

   # We have to catch all the VAR=Funky Text before anything else
   while ( $formula =~ s/([a-z][a-z0-9_]*=[a-z0-9_ =\{\}]*)//i ) {
      my @values = split '=', $1;
      if ( @values > 2 ) {

         # There should only be one = per variable
         $log->warning(
            qq{Too many = in "$1" found in "$tag"},
            $file,
            $line
         );
      }

      # [ 1104117 ] BL is a valid variable, like CL
      elsif ( $values[0] eq 'BL' || $values[0] eq 'CL' ||
         $values[0] eq 'CLASS' || $values[0] eq 'CLASSLEVEL' ) {
         # Convert {} to () for proper validation
         $values[1] =~ tr/{}/()/;
         registerXCheck(
            'CLASS',
            qq(@@" in "$tag),
            $file,
            $line,
            $values[1] );
      }

      elsif ($values[0] eq 'SKILLRANK' || $values[0] eq 'SKILLTOTAL' ) {

         # Convert {} to () for proper validation
         $values[1] =~ tr/{}/()/;
         registerXCheck(
            'SKILL',
            qq(@@" in "$tag),
            $file,
            $line,
            $values[1] );

      } else {

         $log->notice(
            qq{Invalid variable "$values[0]" before the = in "$1" found in "$tag"},
            $file,
            $line
         );
      }
   }

   # Variables begin with a letter or the % and are followed
   # by letters, numbers, or the _
   VAR_NAME:
   for my $var_name ( $formula =~ /([a-z%][a-z0-9_]*)/gi ) {

      # If it's an operator, we skip it.
      if ( index( $var_name, 'MAX'   ) != -1
         || index( $var_name, 'MIN'   ) != -1
         || index( $var_name, 'TRUNC' ) != -1) {

         next VAR_NAME
      };

      push @variable_names, $var_name;
   }

   return @variable_names;
}

=head2 parseJepFormula

   Parse a Jep formula expression and return a list of variables
   found.

   Parameter:  $formula   : String containing the formula
               $tag       : Tag containing the formula
               $file      : Filename to use with ewarn
               $line      : Line number to use with ewarn
               $is_param  : Indicate if the Jep expression is a function parameter

=cut

sub parseJepFormula {
   my ($formula, $tag, $file, $line, $is_param) = @_;

   return () if !defined $formula;

   my @variables_found = ();   # Will contain the return values
   my $last_token      = q{};  # Only use for error messages
   my $last_token_type = q{};

   pos $formula = 0;

   # Get the logger singleton
   my $log = getLogger();

   while ( pos $formula < length $formula ) {

      # If it's an identifier or a function
      if ( my ($ident) = ( $formula =~ / \G ( $isIdentRegex ) /xmsgc ) ) {

         # Identifiers are only valid after an operator or a separator
         if ( $last_token_type && $last_token_type ne 'operator' && $last_token_type ne 'separator' ) {

            # We "eat" the rest of the string and report an error
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $log->notice(
               qq{Jep syntax error near "$ident$bogus_text" found in "$tag"},
               $file,
               $line
            );

         # Indentificator followed by bracket = function
         } elsif ( $formula =~ / \G [(] /xmsgc ) {

            # It's a function, is it valid?
            if ( !$isJepFunction{$ident} ) {
               $log->notice(
                  qq{Not a valid Jep function: $ident() found in $tag},
                  $file,
                  $line
               );
            }

            # Reset the regex position just before the parantesis
            pos $formula = pos($formula) - 1;

            # We extract the function parameters
            my ($extracted_text) = Text::Balanced::extract_bracketed( $formula, '(")' );

            carp $formula if !$extracted_text;

            $last_token = "$ident$extracted_text";
            $last_token_type = 'function';

            # We remove the enclosing brackets
            ($extracted_text) = ( $extracted_text =~ / \A [(] ( .* ) [)] \z /xms );

            # For the var() function, we call the old parser
            if ( $ident eq 'var' ) {
               my ($var_text, $reminder) = Text::Balanced::extract_delimited( $extracted_text );

               # Verify that the values are between ""
               if ( $var_text ne q{} && $reminder eq q{} ) {

                  # Revove the "" and use the extracted text with the old var parser
                  ($var_text) = ( $var_text =~ / \A [\"] ( .* ) [\"] \z /xms );

               } else {

                  # We use the original extracted text with the old var parser
                  $var_text = $extracted_text;

                  $log->notice(
                     qq{Quote missing for the var() parameter in "$tag"},
                     $file,
                     $line
                  );
               }

               # It's a variable, use the old varname operation.
               push @variables_found, oldExtractVariables($var_text, $tag, $file, $line);

            } else {

               # Otherwise, each of the function parameters should be a valid Jep expression
               push @variables_found, parseJepFormula( $extracted_text, $tag, $file, $line, 1 );
            }

         } else {

            # It's an identifier
            push @variables_found, $ident;
            $last_token = $ident;
            $last_token_type = 'ident';
         }

      } elsif ( my ($operator) = ( $formula =~ / \G ( $isOperatorRegex ) /xmsgc ) ) {
         # It's an operator

         if ( $operator eq '=' ) {
            if ( $last_token_type eq 'ident' ) {
               $log->notice(
                  qq{Forgot to use var()? Dubious use of Jep variable assignation near }
                  . qq{"$last_token$operator" in "$tag"},
                  $file,
                  $line
               );

            } else {
               $log->notice(
                  qq{Did you want the logical "=="? Dubious use of Jep variable assignation near }
                  . qq{"$last_token$operator" in "$tag"},
                  $file,
                  $line
               );
            }
         }

         $last_token = $operator;
         $last_token_type = 'operator';

      } elsif ( $formula =~ / \G [(] /xmsgc ) {

         # Reset the regex position just before the bracket
         pos $formula = pos($formula) - 1;

         # Extract what is between the () and call recursivly
         my ($extracted_text) = Text::Balanced::extract_bracketed( $formula, '(")' );

         if ($extracted_text) {

            $last_token = $extracted_text;
            $last_token_type = 'expression';

            # Remove the outside brackets
            ($extracted_text) = ( $extracted_text =~ / \A [(] ( .* ) [)] \z /xms );

            # Recursive call
            push @variables_found, parseJepFormula( $extracted_text, $tag, $file, $line, 0 );

         } else {

            # We "eat" the rest of the string and report an error
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $log->notice(
               qq{Unbalance () in "$bogus_text" found in "$tag"},
               $file,
               $line
            );
         }

      } elsif ( my ($number) = ( $formula =~ / \G ( $isNumberRegex ) /xmsgc ) ) {

         # It's a number
         $last_token = $number;
         $last_token_type = 'number';

      } elsif ( $formula =~ / \G [\"'] /xmsgc ) {

         # It's a string
         # Reset the regex position just before the quote
         pos $formula = pos($formula) - 1;

         # Extract what is between the () and call recursivly
         my ($extracted_text) = Text::Balanced::extract_delimited( $formula );

         if ($extracted_text) {

            $last_token = $extracted_text;
            $last_token_type = 'string';

         } else {

            # We "eat" the rest of the string and report an error
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $log->notice(
               qq{Unbalance quote in "$bogus_text" found in "$tag"},
               $file,
               $line
            );
         }

      } elsif ( my ($separator) = ( $formula =~ / \G ( [,] ) /xmsgc ) ) {

         # It's a comma
         if ( $is_param == 0 ) {
            # Commas are allowed only as parameter separator
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $log->notice(
               qq{Jep syntax error found near "$separator$bogus_text" in "$tag"},
               $file,
               $line
            );
         }

         $last_token = $separator;
         $last_token_type = 'separator';

      } elsif ( $formula =~ / \G \s+ /xmsgc ) {
         # Spaces are allowed in Jep expressions, we simply ignore them

      } else {

         if ( $formula =~ /\G\[.+\]/gc ) {
            # Allow COUNT[something]
         } else {
            # If we are here, all is not well
            my ($bogus_text) = ( $formula =~ / \G (.*) /xmsgc );
            $log->notice(
               qq{Jep syntax error found near unknown function "$bogus_text" in "$tag"},
               $file,
               $line
            );
         }
      }
   }

   return @variables_found;
}



1;
