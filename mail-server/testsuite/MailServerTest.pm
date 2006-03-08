package MailServerTest;
#use warnings;

BEGIN {
    $TYPEINFO{run} = ["function", "void"];
    push @INC, '/usr/share/YaST2/modules/';
}

use YaST::YCP;
use ycp;
use YaPI::MailServer;
use Locale::gettext;
use POSIX ();     # Needed for setlocale()

use Data::Dumper;
use strict;

POSIX::setlocale(LC_MESSAGES, "");
textdomain("MailServer");


sub printError {
    my $err = shift;
    foreach my $k (keys %$err) {
        print STDERR "$k = ".$err->{$k}."\n";
    }
    print STDERR "\n";
    exit 1;
}

sub run {

   print "Hier I am\n";
   my %GS = ( 
                           'Changed'           => '1',
                           'MaximumMailSize'   => 12345678,
                           'Banner'            => 'Das ist mein Mailserver',
                           'SendingMail'   => { 
                                        'Type'      => 'relayhost',
                                        'TLS'       => 'NONE',
                                        'RelayHost'     => {
                                                         'Name'     => 'relay.suse.de',
                                                         'Auth'     => 1,
                                                         'Account'  => 'user',
                                                         'Password' => 'passwd'
                                                       },

                                      },
                         );
  my $GlobalSettings;
  my $ERROR = YaPI::MailServer->WriteGlobalSettings(\%GS,'cn=admin,dc=suse,dc=de','secret');
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
