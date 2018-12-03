package LstTidy::Parse;

use strict;
use warnings;

# Constants for the master_line_type
use constant {
   # Line importance (Mode)
   MAIN           => 1, # Main line type for the file
   SUB            => 2, # Sub line type, must be linked to a MAIN
   SINGLE         => 3, # Idependant line type
   COMMENT        => 4, # Comment or empty line.

   # Line formatting option (Format)
   LINE           => 1, # Every line formatted by itself
   BLOCK          => 2, # Lines formatted as a block
   FIRST_COLUMN   => 3, # Only the first column of the block gets aligned

   # Line header option (Header)
   NO_HEADER      => 1, # No header
   LINE_HEADER    => 2, # One header before each line
   BLOCK_HEADER   => 3, # One header for the block

   # Standard YES NO constants
   NO             => 0,
   YES            => 1,

   # The defined (non-standard) size of a tab
   TABSIZE        => 6,
};

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
   'SOURCEDATE'      => 0,
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

# The file type that will be rewritten.
my %writefiletype = (
   'ABILITY'         => 1,
   'ABILITYCATEGORY' => 1, # Not sure how we want to do this, so leaving off the list for now. - Tir Gwaith
   'BIOSET'          => 1,
   'CLASS'           => 1,
   'CLASS Level'     => 1,
   'COMPANIONMOD'    => 1,
   'COPYRIGHT'       => 0,
   'COVER'           => 0,
   'DEITY'           => 1,
   'DOMAIN'          => 1,
   'EQUIPMENT'       => 1,
   'EQUIPMOD'        => 1,
   'FEAT'            => 1,
   'KIT',            => 1,
   'LANGUAGE'        => 1,
   'LSTEXCLUDE'      => 0,
   'INFOTEXT'        => 0,
   'PCC'             => 1,
   'RACE'            => 1,
   'SKILL'           => 1,
   'SPELL'           => 1,
   'TEMPLATE'        => 1,
   'WEAPONPROF'      => 1,
   'ARMORPROF'       => 1,
   'SHIELDPROF'      => 1,
   '#EXTRAFILE'      => 0,
   'VARIABLE'        => 1,
   'DATACONTROL'     => 1,
   'GLOBALMOD'       => 1,
   'SAVE'            => 1,
   'STAT'            => 1,
   'ALIGNMENT'       => 1,
);

=head2 isParseableFileType

   Returns a code ref that can be used to parse the lst file.

=cut

sub isParseableFileType {
   my ($fileType) = @_;

   return $validfiletype{$fileType};
}

=head2 isWriteableFileType 

=cut

sub isWriteableFileType {
   my $file = shift;

   return $writefiletype{$file};
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
