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
use strict;

POSIX::setlocale(LC_MESSAGES, "");
textdomain("MailServer");



sub run {

   print "Hier I am\n";
   my %GS = ( 
                           'Changed'           => '1',
                           'MaximumMailSize'   => 0,
                           'Banner'            => 'Das ist mein Mailserver',
                           'SendingMail'   => { 
                                        'Type'      => 'relayhost',
                                        'TLS'       => '',
                                        'RelayHost'     => {
                                                         'Name'     => 'relay.suse.de',
                                                         'Auth'     => 1,
                                                         'Account'  => 'user',
                                                         'Password' => 'passwd'
                                                       },

                                      },
                         );
  my $GlobalSettings;
  YaPI::MailServer->WriteGlobalSettings(\%GS,'cn=admin,dc=suse,dc=de','secret');
  $GlobalSettings = YaPI::MailServer->ReadGlobalSettings();
  my $mastercf = YaPI::MailServer->ReadMasterCF();
  my $fsrv = YaPI::MailServer->findService("smtp","smtp");
  print Dumper($fsrv);
  print $GlobalSettings->{'MaximumMailSize'}."\n";
  print $GlobalSettings->{'Changed'}."\n";
  print $GlobalSettings->{'SendingMail'}{'Type'}."\n";
  print $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Name'}."\n";
  return 1;
}
