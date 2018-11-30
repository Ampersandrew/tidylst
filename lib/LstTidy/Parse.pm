package LstTidy::Parse;

use strict;
use warnings;

# Valid filetype are the only ones that will be parsed
# Some filetype are valid but not parsed yet (no function name)
my %validfiletype = (
   'ABILITY'         => \&parseFile,
   'ABILITYCATEGORY' => \&parseFile,
   'BIOSET'          => \&parseFile,
   'CLASS'           => \&parseFile,
   'COMPANIONMOD'    => \&parseFile,
   'DEITY'           => \&parseFile,
   'DOMAIN'          => \&parseFile,
   'EQUIPMENT'       => \&parseFile,
   'EQUIPMOD'        => \&parseFile,
   'FEAT'            => \&parseFile,
   'INFOTEXT'        => 0,
   'KIT'             => \&parseFile,
   'LANGUAGE'        => \&parseFile,
   'LSTEXCLUDE'      => 0,
   'PCC'             => 1,
   'RACE'            => \&parseFile,
   'SKILL'           => \&parseFile,
   'SOURCELONG'      => 0,
   'SOURCESHORT'     => 0,
   'SOURCEWEB'       => 0,
   'SOURCEDATE'      => 0,                      #[ 1584007 ] New Tag: SOURCEDATE in PCC
   'SOURCELINK'      => 0,
   'SPELL'           => \&parseFile,
   'TEMPLATE'        => \&parseFile,
   'WEAPONPROF'      => \&parseFile,
   'ARMORPROF'       => \&parseFile,
   'SHIELDPROF'      => \&parseFile,
   'VARIABLE'        => \&parseFile,
   'DATACONTROL'     => \&parseFile,
   'GLOBALMOD'       => \&parseFile,
   '#EXTRAFILE'      => 1,
   'SAVE'            => \&parseFile,
   'STAT'            => \&parseFile,
   'ALIGNMENT'       => \&parseFile,
);

=head2 isParseableFileType

   Returns a code ref that can be used to parse the lst file.

=cut

sub isParseableFileType {
   my ($fileType) = @_;

   return $validfiletype{$fileType};
}

=head2 parseFile

   placeholder, will be replaced when the script is split up.

=cut

sub parseFile {
   return 1;
};


=head2 setParseRoutine

   placeholder, will be replaced when the script is split up.

=cut

sub setParseRoutine {
   my ($ref) = @_;

   # Replace the placeholder routines with the routine from the script
   for my $key (keys %validfiletype) {
      if (ref $validfiletype{$key} eq 'CODE') {
         $validfiletype{$key} = ref;
      }
   }
}
