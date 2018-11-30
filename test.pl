#!/usr/bin/perl

use strict;
use warnings;

# expand library path so we can find Pretty modules
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(abs_path $0) . '/lib';

use Pretty::Options ('getOption');

use Pod::Html   (); # We do not import any function for
use Pod::Text   (); # the modules other than "system" modules
use Pod::Usage  ();

my $VERSION        = "7.00.00";
my $VERSION_DATE   = "2018-11-26";
my ($PROGRAM_NAME) = "PCGen PrettyLST";
my ($SCRIPTNAME)   = ( $PROGRAM_NAME =~ m{ ( [^/\\]* ) \z }xms );
my $VERSION_LONG   = "$SCRIPTNAME version: $VERSION -- $VERSION_DATE";

my $today = localtime;

my $return = Pretty::Options::parseOptions(@ARGV);

print "$return";

# Test function or display variables or anything else I need.
if ( getOption('test') ) {

   print "No tests set\n";
   exit;
}

# Fix Warning Level
my $error_message = Pretty::Options::fixWarningLevel();

# Check input path is set
$error_message .= Pretty::Options::checkInputPath(); 

# Redirect STDERR if needed
if (getOption('outputerror')) {
   open STDERR, '>', getOption('outputerror');
   print STDERR "Error log for ", $VERSION_LONG, "\n";
   print STDERR "At ", $today, " on the data files in the \'", getOption('inputpath')  , "\' directory\n";
}

# Diplay usage information
if ( getOption('help') or $Getopt::Long::error ) {
   Pod::Usage::pod2usage(
      {  -msg     => $error_message,
         -exitval => 1,
         -output  => \*STDERR
      }
   );
   exit;
}

# Display the man page
if (getOption('man')) {
   Pod::Usage::pod2usage(
      {  -msg     => $error_message,
         -verbose => 2,
         -output  => \*STDERR
      }
   );
   exit;
}

# Generate the HTML man page and display it

if ( getOption('htmlhelp') ) {
   if( !-e "$PROGRAM_NAME.css" ) {
      generate_css("$PROGRAM_NAME.css");
   }

   Pod::Html::pod2html(
      "--infile=$PROGRAM_NAME",
      "--outfile=$PROGRAM_NAME.html",
      "--css=$PROGRAM_NAME.css",
      "--title=$PROGRAM_NAME -- Reformat the PCGEN .lst files",
      '--header',
   );

   `start /max $PROGRAM_NAME.html`;

   exit;
}

# If present, call the function to generate the "game mode" variables.
if ( getOption('systempath') ne q{} ) {
   Pretty::Conversion::sparse_system_files();
}

# If both an inputpath and an outputpath were given, Verify that the outputpath
# exists
if (getOption('inputpath') && getOption('outputpath') && ! -d getOption('outputpath')) {

   Pod::Usage::pod2usage(
      {
         -msg     => "\nThe directory " . getOption('outputpath') . " does not exist.",
         -exitval => 1,
         -output  => \*STDERR,
      }
   );
   exit;
}


__END__

=head1 NAME

prettylst.pl -- Reformat the PCGEN .lst files

Version: 1.38

=head1 DESCRIPTION

B<prettylst.pl> is a script that parse a PCGEN .lst files and generate
new ones with the proper ordering of the fields. The original order was
given by Mynex. Nowadays, it's Tir-Gwait that is the
head-honcho-master-lst-monkey (well, he decide the order anyway :-).

The script is also able to do some conversions of the .lst so that old
versions are compatibled with the latest release of PCGEN.

=head1 INSTALLATION

=head2 Get Perl

I'm using ActivePerl v5.8.6 (build 811) but any standard distribution with version 5.5 and
over should work. The script has been tested on Windows 98, Windows 2000, Windows XP and FreeBSD.

To my knowledge, I'm using only one module that is not included in the standard distribution: Text::Balanced
(this module is included in the 5.8 standard distribution and maybe with some others).

To get Perl use <L<http://www.activestate.com/Products/ActivePerl/>> or <L<http://www.cpan.org/ports/index.html>>
To get Text::Balanced use <L<http://search.cpan.org/author/DCONWAY/Text-Balanced-1.89/lib/Text/Balanced.pm>> or
use the following command if you use the ActivePerl distribution:

  ppm install text-balanced

=head2 Put the script somewhere

Once Perl is installed on your computer, you just have to find a home for the script. After that,
all you have to do is type B<perl prettylst.pl> with the proper parameters to make it
work.

=head1 SYNOPSIS

  # parse all the files in PATH, create the new ones in NEWPATH
  # and produce a report of the TAG in usage
  perl prettylst.pl -inputpath=<PATH> -outputpath=<NEWPATH> -report
  perl prettylst.pl -i=<PATH> -o=<NEWPATH> -r

  # parse all the files in PATH and write the error messages in ERROR_FILE
  # without creating any new files
  perl prettylst.pl -inputpath=<PATH> -outputerror=<ERROR_FILE>
  perl prettylst.pl -i=<PATH> -e=<ERROR_FILE>

  # parse all the files in PATH and write the error messages in ERROR_FILE
  # without creating any new files
  # A compilation of cross-checking (xcheck) errors will not be displayed and
  # only the messages of warning level notice or worst will be outputed.
  perl prettylst.pl -noxcheck -warninglevel=notice -inputpath=<PATH> -outputerror=<ERROR_FILE>
  perl prettylst.pl -nx -wl=notice -i=<PATH> -e=<ERROR_FILE>

  # parse all the files in PATH and created new ones in NEWPATH
  # by applaying the conversion pcgen5713. The output is redirected
  # to ERROR_FILE
  perl prettylst.pl -inputpath=<PATH> -outputpath=<NEWPATH> \
				-outputerror=<ERROR_FILE> -convert=pcgen5713
  perl prettylst.pl -i=<PATH> -o=<NEWPATH> -e=<ERROR_FILE> -c=pcgen5713

  # display the usage guide lines
  perl prettylst.pl -help
  perl prettylst.pl -h
  perl prettylst.pl -?

  # display the complete documentation
  perl prettylst.pl -man

  # generate and attemp to display a html file for
  # the complete documentation
  perl prettylst.pl -htmlhelp

=head1 PARAMETERS

=head2 B<-inputpath> or B<-i>

Path to an input directory that will be scanned for .pcc files. A list of
files to parse will be built from the .pcc files found. Only the known filetypes will
be parsed.

If B<-inputpath> is given without any B<-outputpath>, the script parse the files, produce the
warning messages but doesn't write any new files.

=head2 B<-basepath> or B<-b>

Path to the base directory use to replace the @ character in the .PCC files. If no B<-basepath> option is given,
the value of B<-inputpath> is used to replace the @ character.

=head2 B<-systempath> or B<-s>

Path to the B<pcgen/system> used for the .lst files in B<-inputpath>. This directory should contain the
game mode files. These files will be parse to get a list of valid alignment abbreviations, valid statistic
abbriviations, valid game modes and globaly defined variables.

If the B<-gamemode> parameter is used, only the system files found in the proper game mode directory will
be parsed.

=head2 B<-outputpath> or B<-o>

Only used when B<-inputpath> is defined. B<-outputpath> define where the new files will
be writen. The directory tree from the B<-inputpath> will be reproduce as well.

Note: the output directory must be created before calling the script.

=head2 B<-outputerror> or B<-e>

Redirect STDERR to a file. All the warning and errors found by this script are printed
to STDERR.

=head2 B<-gamemode> or B<-gm>

Apply a filter on the GAMEMODE values and only read and/or reformat the files that
meet the filter.

e.g. -gamemode=35e

=head2 B<-convert> or B<-c>

Activate some conversions on the files. The converted files are written in the directory specified
by B<-outputpath>. If no B<-outputpath> is provided, the conversion messages are displayed but
no actual conversions are done.

Only one conversion may be activate at a time.

Here are the list of the valid conversions so far:

=over 12

=item B<pcgen60>

=over 16

Use to change a number of conversions needed for stable 6.0

=item * [ 1973497 ] HASSPELLFORMULA is deprecated

=over 12

=item B<pcgen5120>

=over 16

Use to change a number of conversions for stable 5.12.0.

B<This has a small issue:> if ADD:blah| syntax items that contain ( ) in the elements, it will attempt to convert again.  This has only caused a few problems in the srds, but it is something to be aware of on homebrews.

=item * [ 1678570 ] Correct PRESPELLTYPE syntax

- changes PRESPELLTYPE format from PRESPELLTYPE:<A>,<x>,<y> to standard PRExxx:<x>,<A>=<y>

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1678570&group_id=25576&atid=750093>>

=item * [ 1678577 ] ADD: syntax no longer uses parens

- Converts ADD:xxx(choice)y to ADD:xxx|y|choice.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1678577&group_id=25576&atid=750093>>

=item * [ 1689538 ] Conversion: Deprecation of FOLLOWERALIGN

- Changes the FOLLOWERALIGN tag to new DOMAINS tag imbedded PREALIGN tags.
This can also be done on its own with conversion 'followeralign'.

=item * [ 1353255 ] TYPE to RACETYPE conversion

Use to change the TYPE entry in race.lst to RACETYPE if no RACETYPE is present.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1353255&group_id=25576&atid=750093>>


=item * [ 1324519 ] ASCII characters

- Converts a few known upper level characters to ASCII standard output
characters to prevent crashes and bad output when exporting from PCGen.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1324519&group_id=25576&atid=750093>>

=back

=item B<followeralign>

Use to change the FOLLOWERALIGN tag to the new DOMAINS tag imbedded PREALIGN tags.  This is included in conversion 5120

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1689538&group_id=25576&atid=750093>>

=item B<racetype>

Use to change the TYPE entry in race.lst to RACETYPE if no RACETYPE is present.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1353255&group_id=25576&atid=750093>>

=item B<pcgen5713>

Use to apply the conversions that bring the .lst files from v5.7.4 of PCGEN
to vertion 5.7.13.

=over 16

=item * [ 1070084 ] Convert SPELL to SPELLS

The old SPELL tags have been deprecated and must be replaced by SPELLS. This conversion
does only part of the job since not all the information needed by the new SPELLS tags
is present in the old SPELL tags.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=1070084&group_id=36698&atid=450221>>

=item * [ 1070344 ] HITDICESIZE to HITDIE in templates.lst

The old HITDICESIZE tag has been deprecated and my be replaced by the new HITDIE. HITDICESIZE
was only present in the TEMPLATE files.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=1070344&group_id=36698>>

=item * [ 731973 ] ALL: new PRECLASS syntax

All the PRECLASS tags -- including the ones found within BONUS tags -- are converted to the new
syntax -- B<PRECLASS:E<lt>number of classesE<gt>,E<lt>list of classesE<gt>=E<lt>levelE<gt>>.

Note: this conversion was done a long time ago (pcgen511) but I've reactivated it since
a lot of old PRECLASS formats have reaappeared in the data sets resently.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=731973&group_id=36698&atid=450221>>

=back

=item B<pcgen574>


Use to apply the conversions that bring the .lst files from v5.6.x or v5.7.x of PCGEN
to vertion 5.7.4.

=over 16

=item * [ 876536 ] All spell casting classes need CASTERLEVEL

Add BONUS:CASTERLEVEL tags to casting classes that do not already have it.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=876536&group_id=36698&atid=417816>>

=item * [ 1006285 ] Convertion MOVE:<number> to MOVE:Walk,<Number>

The old MOVE tags are changed to the proper syntax i.e. the syntax that
identify the type of move. In this case, we assume that if no move
type was given, the move type is Walk.

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=1006285&group_id=36698>>

=back

=item B<pcgen56>

Use to apply the conversions that bring the .lst files from v5.4.x of PCGEN
to vertion 5.6.

=over 16

=item * [ 892746 ] KEYS entries were changed in the main files

Attempt at automatically conerting the KEYS entries that were changed in the
main xSRD files. Not all the changes were covered though.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=892746&group_id=36698&atid=578825>>

=back

=item B<pcgen555>

Use to apply the conversions that bring the .lst files from v5.4.x of PCGEN
to vertion 5.5.5.

=over 16

=item * [ 865826 ] Remove the deprecated MOVE tag in EQUIPMENT files

The MOVE tags are removed from the equipments files since they are now useless there.

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=865826&group_id=36698>>

=back

=item B<pcgen541>

Use to apply the conversions that bring the .lst files from v5.4 of PCGEN
to vertion 5.4.1.

=over 16

=item * [ 845853 ] SIZE is no longer valid in the weaponprof files

SIZE is removed from WEAPONPROF files and is not replaced.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=845853&group_id=36698&atid=578825>>

=back

=item B<pcgen54>

Use this switch to convert from PCGEN 5.2 files to PCGGEN 5.4.

B<WARNING>: Do B<not> use this switch with B<CMP> files! You will break them.

=over 16

=item * [ 707325 ] PCC: GAME is now GAMEMODE

Straight change from one tag to the other. Why? Beats me but it sure helps the conversion script
buisiness to prosper :-).

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=707325&group_id=36698>>

=item * [ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB

This change is needed to allow users to completely replace the BAB formulas with something
of their choice. For example, users can now have a customized class with
B<BONUS:COMBAT|BAB|TL|TYPE=Base> that would replace all the other Base bonus to BAB
(because it is greater).

<L<http://sourceforge.net/tracker/?func=detail&atid=450221&aid=784363&group_id=36698>>

=item * [ 825005 ] convert GAMEMODE:DnD to GAMEMODE:3e

PCGEN is droping the d20 licence. Because of that, the DnD keyword can no longer be used
as a game mode. As of PCGEN 5.4, the change to the system files were done and all the
.PCC files that linked to B<GAMEMODE:DnD> must now link to B<GAMEMODE:3e>.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=825005&group_id=36698>>

B<WARNING>: Do B<not> use this conversion with B<CMP> files! You will break them.

=item * [ 831569 ] RACE:CSKILL to MONCSKILL

The new MONCSKILL tag along with the MFEAT and MONSTERCLASS are used when the default monsters
opotion is enabled in the PCGEN pref. Otherwise, the FEAT and CSKILL tags are used.

<L<http://sourceforge.net/tracker/?func=detail&atid=578825&aid=831569&group_id=36698>>

=back

=item B<pcgen534>

The following conversions were done on the .lst files between version 5.1.1 and 5.3.4 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 707325 ] PCC: GAME is now GAMEMODE

All the B<GAME> tags in the B<.PCC> files are converted to B<GAMEMODE> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=707325&group_id=36698>>

=item * [ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB

All the B<BONUS:COMBAT|BAB> related to classes now have a B<TYPE=Base.REPLACE> added to them. This is
an important conversion if you want to mix files with the files included with PCGEN. If this is not done,
the BAB calculation will be all out of wack and you won't really know why.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=784363&group_id=36698>>

=back

=item B<pcgen511>

The following conversions were done on the .lst files between version 4.3.4 and 5.1.1 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 699834 ] Incorrect loading of multiple vision types

=item * [ 728038 ] BONUS:VISION must replace VISION:.ADD

The B<VISION> tag used to allow the B<,> as a separator. This is no longer the case. Only the B<|>
can now be used as a separator. This conversion will replace all the B<,> by B<|> in the B<VISION>
tags except for those using the B<VISION:.ADD> syntax. The B<VISION:.ADD> tags are replaced by
B<BONUS:VISION> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=417816&aid=699834&group_id=36698>>
<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=728038&group_id=36698>>

=item * [ 731973 ] ALL: new PRECLASS syntax

All the PRECLASS tags -- including the ones found within BONUS tags -- are converted to the new
syntax -- B<PRECLASS:E<lt>number of classesE<gt>,E<lt>list of classesE<gt>=E<lt>levelE<gt>>.

<L<http://sourceforge.net/tracker/index.php?func=detail&aid=731973&group_id=36698&atid=450221>>

=back

=item B<pcgen438>

The following conversions were done on the .lst files between version 4.3.3 and 4.3.4 of PCGEN. See
the links for more information about the conversions in question.

=over 16

=item * [ 686169 ] remove ATTACKS: tag

The B<ATTACKS> tags in the EQUIPMENT line types are replaced by B<BONUS:COMBAT|ATTACKS|> tags.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=686169&group_id=36698>>

=item * [ 695677 ] EQUIPMENT: SLOTS for gloves, bracers and boots

The equipment of type Glove, Bracer and Boot needs a B<SLOTS:2> tag if the pair must
be equiped to give the bonus. The conversion looks at the equipement name and adds
the B<SLOTS:2> tag if the item is in the plural form. If the equipment name is in the
singular, a message is printed to show that fact but the SLOTS:2 tag is not added.

<L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=695677&group_id=36698>>

=item * PRESTAT now only accepts the format PRESTAT:1,<stat>=<n>

The B<PRESTAT> no longer accepts the old syntax. Now, every B<PRESTAT> tag needs a leading
number and coma before the stats enumaration. e.g. B<PRESTAT:STR=13> becaumes B<PRESTAT:1,STR=13>.

No tracker found.

=back

=item B<pcgen433>

This convert the references to equipement names and path that were changed with the release 4.3.3 of
PCGEN. This only changes the path values in the .PCC, the files stay in the directories they are found.

=back

=head2 B<-old_source_tag>

From PCGen version 5.9.6, there is a new format for the SOURCExxx tag that use the tab instead of the |. prettylst.pl
automatically converts the SOURCExxx tags to the new format. The B<-old_source_tag> option must be used if
you want to keep the old format in place.

=head2 B<-report> or B<-r>

Produce a report of the valid tags found in all the .lst and .pcc files. The report for
the invalid tags is always printed.

=head2 B<-xcheck> or B<-x>

B<This option is now on by default>

Verify the existance of values refered by other tags and produce a report of the
missing/inconsistant values.

=head2 B<-nojep>

Disable the new parse_jep function for the formula. This makes the script use the
old style formula parser.

=head2 B<-noxcheck> or B<-nx>

Disable the cross-check validations.

=head2 B<-warninglevel> or B<-wl>

Select the level of warning that should be displayed. The more critical levels include
the less critical ones. ex. B<-wl=informational> will output messages of level
informational, notice, warning and error but will not output the debug level messages.

The possible levels are:

=over 12

=item B<error>, B<err> or B<3>

Critical errors that need to be checked otherwise the resulting .lst files will not
work properly with PCGen.

=item B<warning>, B<warn> or B<4>

Important messages that should be verified. All the conversion messages are
at this level.

=item B<notice> or B<5>

The normal messages including common syntax mistakes and unknown tags.

=item B<informational>, B<info> or B<6> (default)

Can be very noisy. Include messages that warn about style, best practice and deprecated tags.

=item B<debug> or B<7>

Messages used by the programmer to debug the script.

=back

=head2 B<-exportlist>

Generate files which list objects with a reference on the file and line where they are located.
This is very useful when correcting the problems found by the -x options.

The files generated are:

=over 12

=item * class.csv

=item * domain.csv

=item * equipment.csv

=item * equipmod.csv

=item * feat.csv

=item * language.csv

=item * pcc.csv

=item * skill.csv

=item * spell.csv

=item * variable.csv

=back

=head2 B<-missingheader> or B<-mh>

List all the requested headers (with the get_header function) that are not
defined in the %tagheader hash. When a header is not defined, the tag name
is used as is in the generated header lines.

=head2 B<-help>, B<-h> or B<-?>

Print a brief help message and exits.

=head2 B<-man>

Prints the manual page and exits. You might want to pipe the output to your favorite pager
(e.g. more).

=head2 B<-htmlhelp>

Generate a .html file with the complete documentation (as it is)
for the script and tries to display it in a browser. The display portion only
works on the Windows platform.


=head1 MANIFEST

The distribution of this script includes the following files:

=over 8

=item * prettylst.pl

The script itself.

=item * prettylst.pl.html

HMTL version of the perldoc for the script. You can generate this file
by typing C<perl prettylst.pl -htmlhelp>.

=item * prettylst.pl.css

Style sheet files for prettylst.pl.html

=item * prettylst-release-notes-135.html

The release notes for the curent version.

=item * prettylst.pl.sig

PGP signature for the script. You can get a copy of my
key here: <L<http://pgp.mit.edu:11371/pks/lookup?op=get&search=0x5187D5D2>>

=back

=head1 COPYRIGHT

Copyright 2002 to 2006 by E<Eacute>ric E<quot>Space MonkeyE<quot> Beaudoin -- <mailto:beaudoer@videotron.ca>

Copyright 2006 to 2010 by Andrew E<quot>Tir GwaithE<quot> McDougall -- <mailto:tir.gwaith@gmail.com>

Copyright 2007 by Richard Bowers

Copyright 2008 Phillip Ryan

All rights reserved.  You can redistribute and/or modify
this program under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>.

=head1 TO DO

=over 8

=item * Default monster race conversion to KITs

=item * Add better examples

=item * Add more cross-reference checks

=item * Add more Ability object checks

=back

=head1 KNOWN BUGS

=over 8

=item * When running conversions pcgen5120 on a file with ADD:xxx|, and the sub-elements contain ( ), prettylst will run the conversion script on that tag again, resulting in too many | in the tag, and no loading in pcgen.  Please be careful and make backups before running the script conversion (as usual)

=item * When running coversions pcgen5120, lots of duplicate item warnings when replacing the ADD:xxx syntax.  running the script after that will show better accuracy, but remove the replacement statements in the report.

=item * The script is still unwilling to do the coffee...

=back

=head1 VERSION HISTORY

=head2 v1.40 -- -- NOT YET RELEASED

[ 1973497 ] HASSPELLFORMULA is deprecated

[ 1778050 ] MOVECLONE now only has 3 args

[ 1870825 ] EqMod CHOOSE Changes

[ 2946558 ] TEMPLATE can be used in COMPANIONMOD lines

[ 2596967 ] ABILITY not recognized for MASTERBONUSRACE

[ 2946552 ] New SELECTION Kit Tag

[ 2946555 ] BENEFIT can be used more than once per line

[ 2946551 ] New LANGBONUS Kit tag

[ 1864706 ] PROFICIENCY: requires a subtoken

[ 2577370 ] New Token - ABILITYLIST

[ 2387200 ] New Token - PREPROFWITHARMOR

[ 2577310 ] New Token - PREPROFWITHSHIELD

[ 2186450 ] New Ability/Feat Token - ASPECT

[ 2544134 ] New Token - SPELLKNOWN

=head2 v1.39 -- 2000.01.28

[ 2022217 ] UMULT is valid in Abillities

[ 2016715 ] ADD tags are not as globally applied as they should be

[ 2016696 ] PRECAMPAIGN tag for .pcc and lst files

[ 2012989 ] Kit TYPE tag

Added an audible notification {beep} when processing completes

[ 1941853 ] Allow , in Spell Knowledge feat

[ 1998298 ] SPELLS TIMEUNIT checking bug

[ 1997408 ] False positive: TIMEUNIT= parameter is missing

[ 1958876 ] PL not dealing with JEP syntax correctly

[ 1958872 ] trim PREXXX before checking SPELLLEVEL

[ 1995252 ] Header for the Error Log

[ 1994059 ] Convert EQMOD "BIND" to "BLIND"

[ 1938933 ] BONUS:DAMAGE and BONUS:TOHIT should be Deprecated

[ 1905481 ] Deprecate CompanionMod SWITCHRACE

[ 1888288 ] CHOOSE:COUNT= is deprecated

[ 1870482 ] AUTO:SHIELDPROF changes

[ 1864704 ] AUTO:ARMORPROF|TYPE=x is deprecated

[ 1804786 ] Deprecate SA: replace with SAB:

[ 1804780 ] Deprecate CHOOSE:EQBUILDER|1

[ 1992156 ] CHANGEPROF may be used more than once on a line

[ 1991974 ] PL incorectly reports CLEARALL as CLEAR

[ 1991300 ] Allow %LIST as a substitution value on BONUS:CHECKS

[ 1973526 ] DOMAIN is supported on Class line

[ 1973660 ] ADDDOMAINS is supported on Class lines

[ 1956721 ] Add SERVESAS tag to Ability, Class, Feat, Race, Skill files

[ 1956719 ] Add RESIZE tag to Equipment file

[ 1956220 ] REPEATLEVEL not recognized as a ClassLevel line

[ 1956204 ] Check for both TYPE:Container and CONTAINS in Equipment files

[ 1777282 ] CONTAINS Unlimited Weight is UNLIM, not -1

[ 1946006 ] Add BONUS:MISC to Spell

[ 1943226 ] Add UDAM to EQUIPMENT tag list

[ 1942824 ] LANGAUTO .CLEARALL and .CLEAR

[ 1941843 ] Reduce Spellbook warning to info

[ 1941836 ] NONE is valid for SPELLSTAT

[ 1941831 ] PREMULT can be used multiple times

[ 1941829 ] AUTO:FEAT can be used multiple times

[ 1941208 ] Preliminary work toward supporting the processing of the AbilityCategory lst files.

[ 1941207 ] Add the Global tag GENDER to the CLASS, RACE, and TEMPLATE tag lists

[ 1757241 ] CAMPAIGN not a recognized *.pcc tag -- Could not duplicate this issue

Added several new column headers

[ 1937985 ] Add TIMEUNIT=<text> parameter to the SPELLS tag

[ 1937852 ] Kit GENDER Support

[ 1937680 ] KIT FUNDS lines in Kit file

[ 1750238 ] ABILITY warnings

[ 1912505 ] Stop Reporting missing TYPE and RACETYPE in racial .MOD

[ 1729758 ][BUG]DOMAIN tags with PREALIGN cause false positive xcheck

[ 1935376 ] New files: Armorprof and Shieldprof

[ 1774985 ] Exchange cl() with classlevel()

[ 1864711 ] Convert ADD:SA to ADD:SAB

[ 1893278 ] UNENCUMBEREDMOVE is a global tag

[ 1893279 ] HASSPELLFORMULA Class Line tag

[ 1805245 ] NATURALATTACKS allowed more than once in RACE

[ 1776500 ] PREDEITY needs updated

[ 1814797 ] PPCOST needs to be added as valid tag in SPELLS

[ 1786966 ] Global tags throwing false warnings

[ 1784583 ] .MOD .FORGET .COPY race lines don't need RACETYPE or TYPE

[ 1718370 ] SHOWINMENU tag missing for PCC files

[ 1722300 ] ABILITY tag in different locations

[ 1722847 ] AUTO:WEAPONPROF in equipment.lst

=head2 v1.38 -- 2007.04.26

=over 3

=item Additional Conversions:

[ 1678570 ] Correct PRESPELLTYPE syntax

[ 1678577 ] ADD: syntax no longer uses parens

[ 1689538 ] Conversion: Deprecation of FOLLOWERALIGN
- Use "Followeralign" as the option to convert to invoke this.

[ 1514765 ] Conversion to remove old defaultmonster tags

[ 1324519 ] ASCII characters

=back

=over 3

=item Additional Warnings and notices:

[ 1671407 ] xcheck PREABILITY tag

[ 1683231 ] CHOOSE:SCHOOLS does not have arguments

[ 1695877 ] KEY tag is global

[ 1596310 ] xcheck: TYPE:Spellbook for equip w/ NUMPAGES and PAGEUSAGE

[ 1368562 ] .FORGET / .MOD don\'t need KEY entries

[ 1671410 ] xcheck CATEGORY:Feat in Feat object.

[ 1690990 ] Add APPEARANCE to Deities LST

[ 1223873 ] WEAPONAUTO is no longer valid

[ 1678573 ] ADD: deprecation

[ 1678576 ] ADD:FEAT supports ALL

[ 1387361 ] No KIT STARTPACK entry for \"KIT:xxx\"

Race entry references with % now produce _much_ fewer errors lines.

=back

=head2 v1.37 -- 2007.03.01

[ 1353255 ] TYPE to RACETYPE conversion
- Use convert 'racetype' to invoke this.

[ 1672551 ] PCC tag COMPANIONLIST

[ 1672547 ] Support for Substitution Classes

[ 1683839 ] Sort KEY tags next to names

=head2 v1.37 -- 2007.03.01

[ 1623708 ] Invalid value "DEITY" for tag "PREALIGN" - should be allowed

[ 1374892 ] DEITY tag

Ability file now supported, including LEVELABLITY in Kits.  No real checking yet.

[ 1671827 ] PRESRxx enhancement

[ 1666665 ] Add support for ABILITY files

[ 1658571 ] KIT in feats and prettylst

[ 1671364 ] missing valid TEMPLATE tags

[ 1671363 ] missing SPELL line tags

[ 1671361 ] new PCC tag; ISMATURE:<YES/NO>

[ 1671356 ] Missing valid tags for Companion support

[ 1671353 ] add missing BONUS:SLOTS parameters

[ 1326023 ] New tag: BONUS:MONSKILLPTS|LOCKNUMBER|x

[ 1661050 ] New PREAGESET tag

=head2 v1.36 -- 2007.01.26

[ 1637309 ] REACH, FACE & LEGS are now Template tags

[ 1630261 ] Change syntax for QUALIFY tag

[ 1615457 ] Replace ALTCRITICAL with ALTCRITMULT

Add PREREACH tag

[ 1625250 ] New tag REACHMULT:x

=head2 v1.35

[ 1593904 ] KIT lines can have any standard PRE tag

[ 1596402 ] New Kit GEAR tag: LOOKUP

[ 1596400 ] New Kit line_type: TABLE, with VALUES tag

[ 1593894 ] New Kit tag: OPTION

[ 1593885 ] New Kit line_type tag: SELECT

[ 1593872 ] False warning: No SKILL entry for CSKILL:ALL

[ 1594671 ] New tag: equipmod FORMATCAT

[ 1594651 ] New Tag: Feat.lst: DESC:.CLEAR and multiple DESC tags

[ 1593868 ] New equipment tag "QUALITY"

[ 1593879 ] New Kit tag: APPLY

[ 1593907 ] False warning: Invalid value "CSHEET" for tag "VISIBLE"

Moved SOURCExxx tag info into array - all lines use same tag order for SOURCE tags now.

[ 1584007 ] New Tag: SOURCEDATE in PCC

[ 1450980 ] New Spellbook tags

[ 1335912 ] New tag: TEMPLATE:.CLEAR

[ 1580059 ] SKILLLIST tag

[ 1173567 ] Convert old style PREALIGN to new style

[ 1105603 ] New VARs in gameMode files

[ 1117152 ] VFEAT and TEMPLATE use

[ 1119767 ] Invalid value "R" for tag "MODS"

[ 1123650 ] HITDIE tag in class lines

[ 1152687 ] SPELLLEVEL:CLASS in feats.lst

[ 1153255 ] FUMBLERANGE new tag

[ 1156423 ] BONUS:WIELDCATEGORY

[ 1173534 ] .CLEAR syntax issue

[ 1173794 ] BONUS:WEAPONPROF order in race file

Eliminated a lot of false positive with references to SUBCLASS

Psionic is now valid in ADD:SPELLCASTER

Clean up the valid game modes

[ 1326008 ] Add tag: HIDETYPE to the PCC tag list

[ 1326016 ] New tag: PRERULE

[ 1325996 ] Add tag: ADD:EQUIP(y,y)z

[ 1325943 ] ADD:SKILL(Speak Language)1" found in FEAT

[ 1238595 ] New tag: PRECSKILL

[ 1326349 ] Missing TYPE:.CLEAR tag in FEAT

[ 1223873 ] WEAPONAUTO is no longer valid

[ 1326374 ] Add JEP operators

[ 1224428 ] No RACE entry for "SWITCHRACE:xxx"

[ 1282532 ] ClassDefense and Reputation

[ 1292967 ] TITLE and WORSHIPPERS in deity.lst

[ 1327238 ] Add CHANGEPROF to TEMPLATE tag list

[ 1324532 ] Biosettings.lst

[ 1309116 ] LANGAUTO missing in CLASS Level

Removed all the sub prototypes [Perl Best Practices]

mywarn has been completely replaced with ewarn

[ 1324512 ] BONUSSPELLSTAT is not in the CLASS tag list

[ 1355958 ] New tag: SCHOOL:.CLEAR

[ 1353231 ] New tag: RACETYPE

[ 1353233 ] New tag: RACESUBTYPE

[ 1355994 ] KIT file refinements

[ 1356139 ] UDAM missing in FEAT tag list

[ 1356143 ] ADD:Language missing in TEMPLATE tag

[ 1356158 ] SPELL is invalid as value for SPELLSTAT in CLASS

[ 1356999 ] Use of uninitialized value in string eq

[ 1359467 ] .COPY=<name> not used for validation

[ 1361057 ] Missing variables for the Modern game mode

[ 1361066 ] Do not x-check outside the -inputpath

Added system files parsing to find the variables names, game moes, and
abbreviations for stats and alignments

[ 1362206 ] [CLASS Level]Missing TEMPDESC tag

[ 1362222 ] [RACE]Missing KIT tag

[ 1362223 ] [CLASS Level]Missing BONUS:SLOTS

prettylst.pl no longer tolerate old style formula parser

[ 1364343 ] Multiple PRESPELLCAST tags

PRERACE:<number>,<list of races> is officialy the way to go

PRERACE:<list of races> to PRERACE:1,<list of races> conversion

[ 1367569 ] SYSTEM: Validate BONUS:CHECK with statsandchecks.lst values

[ 1366753 ] [KIT] The tag FREE is missing in the KIT FEAT tag list

[ 1398237 ] ALL: Convert Willpower to Will

Filter out the Subversion system directories

The SOURCExxx tags are now separated by tabs instead of |

The -old_source_tag option has been added to use | instead of tab in the SOURCExxx lines

Implemented a "fix" for the /../ in directories

[ 1440104 ] Ignore specific hidden files and directories

[ 1444527 ] New SOURCE tag format

[ 1483739 ] [CMP] SOURCEx changes for 5.10 compatibility

[ 1418243 ] RANGE:.CLEAR is missing in SPELL tag list

[ 1461407 ] ITEM: spell tag order

=head2 v1.34 -- 2005.01.19

[ 1028284 ] Verified if , are present in object names

[ 1028919 ] Report with GAMEMODE

[ 1028285 ] Convert old style PRExxx tags to new style

[ 1039028 ] [PCC]New Xcrawl Game Mode

[ 1070084 ] Convert SPELL to SPELLS

[ 1037456 ] Move BONUS:DC on class line to the spellcasting portion

[ 1027589 ] TEMPDESC (tag from 5.5.1) in skills.lst

[ 1066352 ] BONUS:COMBAT|INITIATIVE on MASTERBONUSRACE line

[ 1066355 ] BONUS tags in spells.lst

[ 1066359 ] BONUS:UDAM in class.lst

[ 1048297 ] New Tag: MONNONSKILLHD

[ 1077285 ] ALTCRITRANGE tag

[ 1079504 ] PREWIELD in eqmod file

[ 1083339 ] RATEOFFIRE in equip.lst

[ 1080142 ] natural attacks with TYPE:Natural

[ 1093382 ] Warning for missing param. in SPELLS

Added x-ref check for FOLLOWER and MASTERBONUSRACE in COMPANIONMODE file type

Added x-ref check for RACE with the PRERACE and !PRERACE tags

[ 1093134 ] BONUS:FEAT|POOL|x

[ 1094126 ] Make -xcheck option on by default

[ 1097487 ] MONSKILL in class.lst

[ 1104117 ] BL is a valid variable, like CL

[ 1104126 ] SPELLCASTER.Psionic is valid spellcasting class type

General work on KIT support

Three new file types added to exportlist: DEITY, KIT and TEMPLATE

DEITY, STARTPACK KIT and TEMPLATE are now validated by the x-check code

[ 1355926 ] DESC on equipment files

=head2 v1.33 -- 2004.08.29

[ 876536 ] All spell casting classes need CASTERLEVEL

[ 1003585 ] PCC: The script should not remove INCLUDE and EXCLUDE

The script can no longer read CLASSSPELL and CLASSSKILL files.

The functions CLASS_parse, CLASSSPELL_parse and GENERIC_parse have been removed since
they were no longer used.

[ 1004050 ] Spycrat is a new valid GAMEMODE

[ 971744 ] 5.7+ TEMPLATE in feats.lst

[ 976475 ] Missing LANGBONUS tag in CLASS Level

[ 1004081 ] Missing global BONUS:CASTERLEVEL

Major code reengeering to allow a better PRExxx tag validation

[ 1004893 ] ADD:SPELLCASTER is valid in RACE

[ 1005363 ] Validate NATURALATTACKS tag

[ 1005651 ] ADD:Language in a feat file

[ 1005653 ] Multiple variable names in a BONUS:VAR tag

[ 1005655 ] BONUS:SLOTS in race files

[ 1005658 ] BONUS:MOVEMULT

[ 1006285 ] Convertion MOVE:<number> to MOVE:Walk,<Number>

[ 1005661 ] ADD:SPELLCASTER in feat .lst

[ 1006985 ] Spycraft gameMode DEFINEd VARiables

[ 1006371 ] SA tag in Skill .lst

[ 976474 ] DEITY tag is missing from CLASS Level

Added the -gamemode parameter

=head2 v1.32 -- 2004.07.06

[ 832164 ] Adding NoProfReq to AUTO:WEAPONPROF for most races

[ 832171 ] AUTO:* needs to be separate tags

Added the -c=skillbonusfix to add BONUS:SKILL|Climb|8|TYPE=Racial if it is not already
present and the race has a MOVE:Climb entry. Same thing with Swim.

[ 845853 ] SIZE is no longer valid in the weaponprof files

[ 833509 ] All the PRExxx tags missing must be added

[ 849366 ] VFEAT with inline PRExxx

Added the ability to export the LANGUAGE entities when using the -exportlist option

[ 865826 ] Remove the deprecated MOVE tag in EQUIPMENT files

[ 865948 ] Properly check files with same name but different directory

[ 849365 ] CLASSES:ALL

[ 849369 ] SPELLCASTER.Arcane=1

[ 879467 ] AUTO:EQUIP in equipment files

[ 882797 ] SUBCLASS -- NAMEISPI: tag

[ 882799 ] SUBCLASSLEVEL -- add SPELLLEVEL:CLASS tag

[ 892746 ] KEYS entries were changed in the main files

[ 892748 ] Track the EQMOD keys with -x flag

Track the variable names with the -x flag (phase 1)

Put BONUS:CASTERLEVEL on the spell CLASS line

Removed a bunch of old conversion code that is no longer used

[ 971746 ] "PREVARGTEQ" can be used more than once in feats.lst

[ 971778 ] BONUS:UDAM| tag

Implemetend a workaroud for a perl bug => [perl #30058] Perl 5.8.4 chokes on perl -e 'BEGIN { my %x=(); }'

[ 902439 ] PREVISION not in FEAT tag list

[ 975999 ] [tab][space][tab] breaks prettylst

[ 974710 ] AUTO:WEAPONPROF usable multiple times

[ 971782 ] FACE tag in races.lst

Removed a warning message for CHOOSE:SPELLLEVEL

Add the B<-nowarning> option to suppress the warning messages

[ 974693 ] PROHIBITED class tag

=head2 v1.31 -- 2003.10.29

[ 823221 ] SPELL multiple time on equipment

[ 823763 ] BONUS:DC in class level

[ 823764 ] ADD:FEAT in domain list

[ 824975 ] spells.lst - DESCISPI:[YES/NO]

[ 825005 ] convert GAMEMODE:DnD to GAMEMODE:3e

[ 829329 ] Lines get deleted when the line type is not know

[ 829335 ] New LANGAUTO line type for KIT files

[ 829380 ] New Game Mode

[ 831569 ] RACE:CSKILL to MONCSKILL

[ 832139 ] CLASS Level: missing NATURALATTACKS

=head2 v1.30 -- 2003.10.14

[ 804091 ] ADD:FEAT warning

[ 807329 ] PRESIZE warning (for template.lst)

[ 813333 ] MONCSKILL and MONCCSKILL in race.lst

[ 813334 ] PREMULT

[ 813335 ] ACHECK:DOUBLE

[ 813337 ] BONUS:DC

[ 813504 ] SPELLLEVEL:DOMAIN in domains.lst

[ 814200 ] PRESKILL in SPELL files

[ 817399 ] Tags usable in SUBCLASS

[ 823042 ] not finding files issue

A new B<-baspath> option was added to specify the path that must replace the @ characters in
the .PCC files when that path is different from B<-inputpath>.

[ 823166 ] Missing PREVARNEQ tag

[ 823194 ] PREBASESIZExxx tags

=head2 v1.29 -- 2003.08.23

New tags were added as a result of the big CMP push.

The script now detect the tags that have no values (with the -x option).

PRECLASS:Spellcaster, Spellcaster.Arcane and Spellcaster.Devine are now understood.

Removed the 4.3.3 dir restructure conversion code.

I've activated the KIT files reformating.

The CLASS lines are now reformated in four lines. A new line with all the spell related
tags follow the skill tags.

[ 707325 ] PCC: GAME is now GAMEMODE L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=707325&group_id=36698>

New set_ewarn_header function

New function to take RACE and TEMPLATE that are on multiple lines and bring them back to one line

[ 779821 ] Add quote removal L<https://sourceforge.net/tracker/?func=detail&atid=578825&aid=779821&group_id=36698>

[ 784363 ] Add TYPE=Base.REPLACE to most BONUS:COMBAT|BAB L<https://sourceforge.net/tracker/?func=detail&atid=450221&aid=784363&group_id=36698>

=head2 v1.28 -- 2003.05.04

New line type MASTERBONUSRACE

New validation for the FEAT line type (CHOSE <=> MULT <=> STACK)

[ 728038 ] BONUS:VISION must replace VISION:.ADD

[ 711565 ] BONUS:MOVE replaced with BONUS:MOVEADD (Not definitive yet)

New validation for PRECLASS (make sure the number is there and the class exists)

[ 731973 ] ALL: new PRECLASS syntax

=head2 v1.27 -- 2003.04.03

The B<-inputpath> option is now mandatory

[ 686169 ] remove ATTACKS: tag

[ 695677 ] EQUIPMENT: SLOTS for gloves, bracers and boots

[ 707325 ] PCC: GAME is now GAMEMODE

[ 699834 ] Incorrect loading of multiple vision types

PRESTAT now only accepts the format PRESTAT:1,<stat>=<n>

=head2 v1.26 -- 2002.02.27

[ 677962 ] The DMG wands have no charge

Removed the invalid PREBAB tag

Change the order for the FEAT line type

Dir path conversion for the new SRD files

Upgraded to ActivePerl 635

New EQUIPMENT tag order

Weapon name conversion for PCGEN 4.3.3 for SRD compliance

New B<-convert> parameter

=head2 v1.25 -- 2003.01.27

[ 670554 ] SYNERGY to BONUS:SKILL format

Fixed the CLASSSPELL conversion that was not working with the new parser

Fixed a problem with the Export Lists function (for DOMAIN)

Change the BIOSET conversion code so that the new bioset files are
generated in the output directory

New SKILL line tags order

=head2 v1.24 -- 2003.01.14

BIOSET generation from the AGE, HEIGHT and WEIGHT tags

Added the BIOSET file definition for FILETYPE_parse

New order for SPELL tags

=head2 v1.23 -- 2003.01.06

I'm removed the useles -debug option

Add a bunch of new tags in the SUBCLASSLEVEL (everything in CLASS Level)

I'm now running Perl Dev Kit 5

=head2 v1.22 -- 2002.12.31

The FEAT validation code now deal with |CHECKMULT properly

The FEAT validation code now ignores , between () for ADD:FEAT and PREFEAT

Fixed remaining tr!/!\\! so that they are used only on MSWin32 systems

The new set_mywan_filename is called after each section header to empty the $previousfile
variable within the mywarn closure

=head2 v1.21 -- 2002.12.28

FEAT validation added for the tags FEAT, MFEAT, VFEAT, PREFEAT and ADD:FEAT

[ 657059 ] Verify pipe is the only delimiter:VISION

The tr!/!\\! on the file names printed by mywarn is done only for MSWin32 OS

=head2 v1.20 -- 2002.12.19

[ 653596 ] Add a TYPE tag for all SPELLs (first part, change on hold)

Added the -missingheader command line option to list all the header that do not
have definitions in the %tagheader hash

Only the first SOURCExxx line is replaced when the SOURCE line replacement option
is active

All the filetypes except CLASSSKILL and CLASSSPELL have been
migrated to FILETYPE_parse (KIT is only validated for now)

New .CLEAR code (TAG:.CLEAR are all different tags now)

=head2 v1.19 -- 2002.12.12

[ 602874 ] SAVES tag deprecated, replaced by 3 BONUS:CHECKS|BASE.savename|x|PREDEFAULTMONSTER:Y

The CVS files beginning with .# are now ignored by prettylst

Code to correct the BONUS:STAT|WIL typo (should be BONUS:STAT|WIS)

New NAMEISPI tag in every files

New get_header function

The BONUS:xxx are now considered differents tags (like the ADD:xxx)

[ 609763 ] Convert the old PRECHECKxxx

Added coded to check and standerdize tags with limited possible values

SA:.CLEAR is now a sperate tag than SA: in order to facilitate the sorting

Got rid of the old %validpcctag (replaced by the generic %valid_tags)

[ 619312 ] RACENAME deprecated, convert to OUTPUTNAME

[ 613604 ] CASTAS:name to SPELLLIST:x|name

Added code to standardise the SOURCExxx line in the .lst files
based of the SOURCExxx tags found in the same directory.

Added code to convert the CLASSSKILL files into CLASS CSKILL

[ 620419 ] Added code to flag and display the SA entries that include ','

[ 624885 ] CLASS: remove AGESET tag

[ 626133 ] Convert CLASS lines into 3 lines

Changed the report sort order so that !PRExxx entries are now sorted
right after the corresponding PRExxx.

Added code for CSKILL, LANGAUTO and LANGBONUS tag validation

[ 641912 ] Convert CLASSSPELL to SPELL

New FILETYPE_parser

Removed the now useless -taginfixed option.

New ###Block pragma. It forces a new block for the entities that have
block formatting (FILETYPE_parse only)

Added the KIT filetype

Convertion code for EFFECTS to DESC and EFFECTTYPE to TARGETAREA in the SPELL files

=head2 v1.18 -- 2002.08.31

Conversion of the stat tags in TEMPLATE (STR, DEX, etc.) by BONUS:STAT|...

Removing TYPE=Ability from BONUS:STAT|xxx|y|TYPE=Ability in RACE

Added the COPYRIGHT tags for the PCC files

Conversion of nameCHECK to BONUS:CHECKS|BASE.name in CLASS

Conversion of BAB to BONUS:COMBAT|BAB in CLASS

Remove the GOLD tag from CLASS and TEMPLATE for OGL compliance

New tag MODTOSKILLS

Deprecated INTMODTOSKILLS

Fixed a bug with #EXTRAFILE that was introduced in parse_tag

=head2 v1.17 -- 2002.08.17

New file type COMPANIONMOD

New tag INFOTEXT

Added conversion code for the STATADJx tags

Add a few of the missing GLOBAL tags

Removed a few illigal BONUS type

[ 571276 ] "PRESKILL:1,Knowledge %" replace by "PRESKILL:1,TYPE.Knowledge" in the CLASS lines

[ xxx ] "SUBSA:blah" must become "SA:.CLEAR.blah". The new SA tags
must be put before the existing SA tags.


=head2 v1.16 -- 2002.06.28

Add code to correct the conversion mistake and also corrected the conversion matrice
for the new SKILL tags.

First phase of cross-check validation.

Corrected a bug with the line number.

Add conversion for PRETYPE:Magic to PRETYPE:EQMODTYPE=MagicalEnhancement in the
EQUIPMOD files.

Add -x option to do x-check validation.

Add validation for the .MOD entries.

Add conversion for SR to SPELLRES in SPELL files.

=head2 v1.15 -- 2002.06.20

New option B<-outputerror> to redirect STDERR in a file

Preserve the leading spaces on the first column when the pragma #prettylst:leadingspaces:ignore
is used. The pragma #prettylst:leadingspaces:trim restore normal space triming.

Replace the deprecated PREVAR for PREVARGT.

Add new DOMAIN tags

Add new DEITY tags

Add new RACE tags

PCGEN now check to see if existing comment line exists before adding a new one. Existing
header lines are genereted to reflect the curent TAGs in used.

Add new SKILL tags

Add new SPELL tags

Add new CLASS tags

=head2 v1.14 -- 2002.06.08

The files are now written if there is no other change then the CF corrections

Add the internal WriteLog function

Change the order for the RACE filetype as requested by Andrew McDougall (tir-gwaith)

RACE filetype: convert INIT:xx to BONUS:COMBAT|Initiative|xx and deprecate INIT

CLASS filetype: convert ADD:INIT|xx to BONUS:COMBAT|Initiative|xx and deprecate ADD:INIT

RACE filetype: added code to remove AC and replace it by BONUS:COMBAT|AC|xx|TYPE=NaturalArmor
when needed

EQUIPMENT filetype: added code to replace all the Cost by COST

Add code to deal with .MOD in all the files except CLASS and CLASSSPELL

=head2 v1.13 -- 2002.05.11

Now parse the BONUS tags.

Change the sort of the CLASS Level lines. Multiple tags on the same type are no
longer on the same column.

Skip empty files.

=head2 v1.12 -- 2002.03.23

Add code to replace the BONUS:FEAT, BONUS:VFEAT and FEAT in the EQUIPMENT by
VFEAT.

Remove the empty columns for the CLASS lines.

Added the parse_tag function for all the tags.

Deprecate the NATURALARMOR tag and added code to convert to
BONUS:COMBAT|AC|x|Type=Natural

=head2 v1.11 -- 2002.03.07

Add code to deal with the CR-CR-LF stuff in the .lst files

The comment generated by PCGEN now contains the CVS Revision and Author tags

The CLASS level lines have a new sort order.

Remove CCOST and RREPLACE from tags (these were typos)

Change findfullpath for the new behavior of the @ character in file paths.

Added code to check the GAME and TYPE tags in the .PCC files

Added code to verify the existance of every file for each .PCC

=head2 v1.10 -- 2002.02.27

Bug fixes

=head2 v1.09 -- 2002.02.20

Add a optional check to see if a TAG has been put in a fixed column. If such ':' is
found in one of the fixed column, a warning is printed.

Check for all file extention to find the unlinked files that are not .lst

Add support fot the E<quot>pragmaE<quot> tag #EXTRAFILE

Add code to convert SKILL to BONUS:SKILL in RACE files

The DEITY tag in the CLASS files was deprecated

=head2 v1.08 -- 2002.02.17

Only write the .pcc files that have an extra 0x0d character or white spaces at the
end of the line.

Add support for the new SOURCEPAGE, SOURCEWEB, SOURCELONG and SOURCESHORT tags.

Add conversion code that replace the SOURCE:p. tags by SOURCEPAGE:p. tags.

Add conversion code that remove the ROOT tags in the SKILL files and add the
new format of the TYPE tag.

Remove the ROOT tag from the SKILL filetype. This tag is now deprecate.

Romove any quote found.

=head2 v1.07 -- 2002.02.08

Bug with the WEAPONBONUS tag being there twice for the RACE filetype

Add code to detect if one of the tags is there more then once for
a particular filetype

The odd end of lines (CR-CR-LF) are striped when the files that get rewriten

Produce a list of files not found in the .PCC files

=head2 v1.06 -- 2002.02.07

Add support for CLASSSPELL

Add support for TEMPLATE

Add support for WEAPONPROF

The script now adds a dummy SOURCE:p. tag in some files when none are found.

=head2 v1.05 -- 2002.02.06

Add support for CLASSSKILL files (OK, this one was not very hard...)

Add support for DIETY files

Add support for DOMAIN files

Add support for FEAT files

Add support for LANGUAGE files

Add support for SKILL files

Add support for SPELL files

Unknown tags are kept (including duplicates)

=head2 v1.04 -- 2002.02.05

Add support for RACE files

Add support for EQUIMOD files

Most files are now parse by a Generic parser

Unknown tags are kept (including duplicates)

=head2 v1.03 -- 2002.02.03

Change the sort order for the additionnal lines

=head2 v1.02 -- 2002.02.03

No more empty white spaces between the columns in for the level advancement lines


=head2 v1.01 -- 2002.02.02

Add support for the CLASS files

Check and remove extra space at the end of each tab separated TAG

Add special case for the ADD:adlib tags

=head2 v1.00 -- 2002.01.27

First working version. Only the EQUIPMENT file are supported.
