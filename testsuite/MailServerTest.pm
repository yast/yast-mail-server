package MailServerTest;
#use warnings;

BEGIN {
    $TYPEINFO{run} = ["function", "void"];
    push @INC, '/usr/share/YaST2/modules/';
}

use MailServer;
use Locale::gettext;
use POSIX ();     # Needed for setlocale()

use Data::Dumper;

POSIX::setlocale(LC_MESSAGES, "");
textdomain("MailServer");



sub run {
   my %GS = ( 
                           'Changed' => 'false',
                           'MSize'   => 0,
                           'Relay'   => { 
                                        'Type'      => 'relayhost',
                                        'Security'  => '',
                                        'RHost'     => {
                                                         'Name'     => 'relay.suse.de',
                                                         'Security' => '',
                                                         'Auth'     => 1,
                                                         'Account'  => 'user',
                                                         'Password' => 'passwd'
                                                       },

                                      },
                         );
  my $GlobalSettings;
  MailServer->WriteGlobalSettings(\%GS);
  $GlobalSettings = MailServer->ReadGlobalSettings();
  print $GlobalSettings->{'MSize'}."\n";
  print $GlobalSettings->{'Changed'}."\n";
  print $GlobalSettings->{'Relay'}{'Type'}."\n";
  print $GlobalSettings->{'Relay'}{'RHost'}{'Name'}."\n";
  return 1;
}
