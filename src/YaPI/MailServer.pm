=head1 NAME

YaPI::MailServer

=head1 PREFACE

This package is the public Yast2 API to configure the postfix.
Representation of the configuration of mail-server.
Input and output routines.

=head1 SYNOPSIS

use YaPI::MailServer


=head1 DESCRIPTION

B<YaPI::MailServer>  is a collection of functions that implement a mail server
configuration API to for Perl programs.

=over 2

=cut




package YaPI::MailServer;

use strict;
use vars qw(@ISA);

use ycp;
use YaST::YCP;
use YaPI;
@YaPI::MailServer::ISA = qw( YaPI );

use Locale::gettext;
use POSIX;     # Needed for setlocale()
use Data::Dumper;

setlocale(LC_MESSAGES, "");
textdomain("MailServer");
our %TYPEINFO;
our @CAPABILITIES = (
                     'SLES9'
                    );

YaST::YCP::Import ("SCR");
YaST::YCP::Import ("Service");
YaST::YCP::Import ("Ldap");


#sub _ {
#    return gettext($_[0]);
#}

###
# # Data was modified?
# # We don't have a global modified variable.
#my $modified = 0;
#

##
 #
my $proposal_valid = 0;

##
 # Write only, used during autoinstallation.
 # Don't run services and SuSEconfig, it's all done at one place.
 #
my $write_only = 0;

BEGIN { $TYPEINFO{ReadMasterCF}  =["function", "any"  ]; }
sub ReadMasterCF {
    my $MasterCf  = SCR->Read('.mail.postfix.mastercf');

    return $MasterCf;
}

BEGIN { $TYPEINFO{findService}  =["function", "any"  ]; }
sub findService {
    my ($service, $command ) = @_;

    my $services  = SCR->Read('.mail.postfix.mastercf.findService', $service, $command);

    return $services;
}
=item *
C<$GlobalSettings = ReadGlobalSettings($$AdminPassword)>

 Dump the mail-server Global Settings to a single hash
 Return hash Dumped settings (later acceptable by WriteGlobalSettings ())

 $GlobalSettings is a pointer to a hash containing the basic settings of 
 the mail server.

 %GlobalSettings = (
       'Changed'               => 0,
            Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

       'MaximumMailSize'       => 0,
            Shows the maximum message size in bytes, the mail server will accept 
            to deliver. Setting this value 0 means there is no limit.

       'Banner'                => '$myhostname ESMTP $mail_name'
            The smtpd_banner parameter specifies the text that follows the 220
            code in the SMTP server's greeting banner. Some people like to see
            the mail version advertised. By default, Postfix shows no version.
            You MUST specify $myhostname at the start of the text. That is an
            RFC requirement. Postfix itself does not care.

       'Interfaces'            => ''
            The inet_interfaces parameter specifies the network interface
            addresses that this mail system receives mail on.  By default,
            the software claims all active interfaces on the machine. The
            parameter also controls delivery of mail to user@[ip.address]
       
       'SendingMail'           => {
            In this hash you can define the type of delivery of outgoing emails.
	    
            'Type'          => '',
                Shows the type of the delivery of the outgoing mails. Possible 
                values are: 
	        DNS : Delivery via DNS lookup of the MX records of the
		      destination domain.
		relayhost : Delivery using a relay host
		NONE : There is no delivery of outgoing mails. In this case
		       some other funcions are not avaiable. For example
		       setting of mail transport.
		       
            'TLS'           => '',
	        If delivery via DNS is used you can set how TLS will be used
		for security. Possible values are:
		NONE    : don't use TLS.
		MAY     : TLS will used when offered by the server.
		MUST    : Only connection with TLS will be accepted.
		MUST_NOPEERMATCH  : Only connection with TLS will be accepted, but
		          no strict peername checking accours.
			  
            'RelayHost'     => {
	        If the type of delivery of outgoing emails is set to "relayhost",
		then you have to define the relyhost in this hash.
		
                  'Name'     => '',
		        DNS name or IP address of the relay host.
			
                  'Auth'     => 0,
		        Sets if SASL authentication will be used for the relayhost.
			Possible values are: 0 (no) and 1 (yes).
			
                  'Account'  => '',
		        The account name of the SASL account.
			
                  'Password' => ''
		        The SASL account password
                }
          }
     );

EXAMPLE:

use MailServer;

    my $AdminPassword   = "VerySecure";


=cut

BEGIN { $TYPEINFO{ReadGlobalSettings}  =["function", ["map", "string", "any" ], "string"]; }
sub ReadGlobalSettings {
    my $self            = shift;
    my $AdminPassword   = shift;

    my %GlobalSettings = ( 
                'Changed'               => 0,
                'MaximumMailSize'       => 0,
                'Banner'                => '',
                'SendingMail'           => { 
                         'Type'          => '',
                         'TLS'           => '',
                         'RelayHost'     => {
                                'Name'     => '',
                                'Auth'     => 0,
                                'Account'  => '',
                                'Password' => ''
                              }
                         
                       }
          );

    my $MainCf    = SCR->Read('.mail.postfix.main.table');
    my $SaslPaswd = SCR->Read('.mail.postfix.saslpasswd.table');
    if( ! SCR->Read('.mail.postfix.mastercf') ) {
         return $self->SetError( summary =>_("Couln't open master.cf"),
                                 code    => "PARAM_CHECK_FAILED" );
    }

    # Reading maximal size of transported messages
    $GlobalSettings{'MaximumMailSize'}  = read_attribute($MainCf,'message_size_limit');

    #
    $GlobalSettings{'Banner'}           = `postconf -h smtpd_banner`;
    chomp $GlobalSettings{'Banner'};

    # Determine if relay host is used
    $GlobalSettings{'SendingMail'}{'RelayHost'}{'Name'} = read_attribute($MainCf,'relayhost');

    if($GlobalSettings{'SendingMail'}{'RelayHost'}{'Name'} ne '') {
      # If relay host is used read & set some parameters
            $GlobalSettings{'SendingMail'}{'Type'} = 'relayhost';
        
        # Determine if relay host need sasl authentication
        my $tmp = read_attribute($SaslPaswd,$GlobalSettings{'SendingMail'}{'RelayHost'}{'Name'}); 
        if( $tmp ) {
            ($GlobalSettings{'SendingMail'}{'RelayHost'}{'Account'},$GlobalSettings{'SendingMail'}{'RelayHost'}{'Password'}) 
	                 = split /:/,$tmp;
        }
        if($GlobalSettings{'SendingMail'}{'RelayHost'}{'Account'}  ne '') {
           $GlobalSettings{'SendingMail'}{'RelayHost'}{'Auth'} = 1;
        }
    } else {
	my $smtpsrv = SCR->Execute('.mail.postfix.mastercf.findService',
		{ 'service' => 'smtp',
		  'command' => 'smtp' });
        if( defined $smtpsrv ) {
            $GlobalSettings{'SendingMail'}{'Type'} = 'DNS';
	} else {   
            $GlobalSettings{'SendingMail'}{'Type'} = 'NONE';
	}    
    }
    if( $GlobalSettings{'SendingMail'}{'Type'} ne 'NONE') {
	    my $USE_TLS          = read_attribute($MainCf,'smtp_use_tls');
	    my $ENFORCE_TLS      = read_attribute($MainCf,'smtp_enforce_tls');
	    my $ENFORCE_PEERNAME = read_attribute($MainCf,'smtp_tls_enforce_peername');
	    if($USE_TLS eq 'no' && $ENFORCE_TLS ne 'yes') {
               $GlobalSettings{'SendingMail'}{'TLS'} = 'NONE';
	    } elsif( $ENFORCE_TLS eq 'yes') {
	      if( $ENFORCE_PEERNAME eq 'no'){
                 $GlobalSettings{'SendingMail'}{'TLS'} = 'MUST_NOPEERMATCH';
	      } else {
                 $GlobalSettings{'SendingMail'}{'TLS'} = 'MUST';
	      } 
	    } else {
                 $GlobalSettings{'SendingMail'}{'TLS'} = 'MAY';
	    }
    }	    
    
    return \%GlobalSettings;
}

=item *
C<boolean = WriteGlobalSettings($GlobalSettings)>

Write the mail-server Global Settings from a single hash
@param settings The YCP structure to be imported.
@return boolean True on success

EXAMPLE:

This example shows the setting up of the mail server bsic configuration
using a relay host with SASL authetication and TLS security.
Furthermore there will be set the maximum mail size, which the mail server
will be accept to deliver, to 10MB.

use MailServer;

    my $AdminPassword   = "VerySecure";

    my %GlobalSettings = (
                   'Changed'               => 1,
                   'MaximumMailSize'       => 10485760,
                   'Banner'                => '$myhostname ESMTP $mail_name',
                   'SendingMail'           => {
                           'Type'          => 'relayhost',
                           'TLS'           => 'MUST',
                           'RelayHost'     => {
                                   'Name'     => 'mail.domain.de',
                                   'Auth'     => 1,
                                   'Account'  => 'user',
                                   'Password' => 'password'
                                 }
                         }
             );

   if( ! WriteGlobalSettings(\%GlobalSettings,$AdminPassword) ) {
        print "ERROR in WriteGlobalSettings\n";
   }

=cut

BEGIN { $TYPEINFO{WriteGlobalSettings}  =["function", "boolean",  ["map", "string", "any" ], "string"]; }
sub WriteGlobalSettings {
    my $self               = shift;
    my $GlobalSettings     = shift;
    my $AdminPassword      = shift;

    if(! $GlobalSettings->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }

    my $MaximumMailSize    = $GlobalSettings->{'MaximumMailSize'};
    my $SendingMailType    = $GlobalSettings->{'SendingMail'}{'Type'};
    my $SendingMailTLS     = $GlobalSettings->{'SendingMail'}{'TLS'};
    my $RelayHostName      = $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Name'};
    my $RelayHostAuth      = $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Auth'};
    my $RelayHostAccount   = $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Account'};
    my $RelayHostPassword  = $GlobalSettings->{'SendingMail'}{'RelayHost'}{'Password'};
    my $MainCf             = SCR->Read('.mail.postfix.main.table');
    my $SaslPasswd         = SCR->Read('.mail.postfix.saslpasswd.table');
    if( ! SCR->Read('.mail.postfix.mastercf') ) {
         return $self->SetError( summary =>_("Couln't open master.cf"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Parsing attributes 
    if($MaximumMailSize =~ /[^\d+]/) {
         return $self->SetError( summary =>_("Maximum Mail Size value may only contain decimal number in byte"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    # If SendingMailType ne NONE we have to have a look 
    # at master.cf if smt is started
    if($SendingMailType ne 'NONE') {
       my $smtpsrv = SCR->Execute('.mail.postfix.mastercf.findService',
                   { 'service' => 'smtp',
                     'command' => 'smtp' });
       if(! defined $smtpsrv ) {
           SCR->Execute('.mail.postfix.mastercf.deleteService', { 'service' => 'smtp', 'command' => 'smtp' });
       }
    }
    
    if($SendingMailType eq 'DNS') {
        #Make direkt mail sending
        #looking for relayhost setting from the past 
        my $tmp = read_attribute($MainCf,'relayhost');
        if( $tmp ne '' ) {
            write_attribute($MainCf,'relayhost','');
            write_attribute($SaslPasswd,$tmp,'');
        }
    } elsif ($SendingMailType eq 'relayhost') {
        write_attribute($MainCf,'relayhost',$RelayHostName);
        if($RelayHostAuth){
           write_attribute($SaslPasswd,$RelayHostName,"$RelayHostAccount:$RelayHostPassword");
        }
    } elsif ($SendingMailType eq 'NONE') {
	SCR->Execute('.mail.postfix.mastercf.deleteService', { 'service' => 'smtp', 'command' => 'smtp' });
    } else {
      return $self->SetError( summary =>_("Unknown mail sending type. Allowed values are:").
                                          " NONE | DNS | relayhost",
                              code    => "PARAM_CHECK_FAILED" );
    }
    #Now we write TLS settings if needed
    if($SendingMailTLS eq 'NONE') {
      write_attribute($MainCf,'smtp_use_tls','no');
      write_attribute($MainCf,'smtp_enforce_tls','no');
      write_attribute($MainCf,'smtp_tls_enforce_peername','no');
    } elsif($SendingMailTLS eq 'MAY') {
      write_attribute($MainCf,'smtp_use_tls','yes');
      write_attribute($MainCf,'smtp_enforce_tls','no');
      write_attribute($MainCf,'smtp_tls_enforce_peername','yes');
    } elsif($SendingMailTLS eq 'MUST') {
      write_attribute($MainCf,'smtp_use_tls','yes');
      write_attribute($MainCf,'smtp_enforce_tls','yes');
      write_attribute($MainCf,'smtp_tls_enforce_peername','yes');
    } elsif($SendingMailTLS eq 'MUST_NOPEERMATCH') {
      write_attribute($MainCf,'smtp_use_tls','yes');
      write_attribute($MainCf,'smtp_enforce_tls','yes');
      write_attribute($MainCf,'smtp_tls_enforce_peername','no');
    } else {
      return $self->SetError( summary =>_("Unknown mail sending TLS type. Allowed values are:").
                                          " NONE | MAY | MUST | MUST_NOPEERMATCH",
                              code    => "PARAM_CHECK_FAILED" );
    }

    write_attribute($MainCf,'message_size_limit',$MaximumMailSize);
    write_attribute($MainCf,'smtpd_banner',$GlobalSettings->{'Banner'});

    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.mail.postfix.saslpasswd.table',$SaslPasswd);

    return 1;
}

=item *
C<$MailTransports = ReadMailTransports($AdminPassword)>

  Dump the mail-server Mail Transport to a single hash
  @return hash Dumped settings (later acceptable by WriteMailTransport ())

  $MailTransports is a pointer to a hash containing the mail transport
  definitions.

  %MailTransports  = (
       'Changed'      => 0,
             Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

       'Transports'  => []
             Poiter to an array containing the mail transport table entries.
		       
   );
   
   Each element of the arry 'Transports' has following syntax:

   %Transport       = (
       'Destination'  => '',
           This field contains a search pattern for the mail destination.
           Patterns are tried in the order as listed below:

           user+extension@domain
              Mail for user+extension@domain is delivered through
              transport to nexthop.

           user@domain
              Mail for user@domain is delivered through transport
              to nexthop.

           domain
              Mail  for  domain is delivered through transport to
              nexthop.

           .domain
              Mail for  any  subdomain  of  domain  is  delivered
              through  transport  to  nexthop.  This applies only
              when the string transport_maps is not listed in the
              parent_domain_matches_subdomains configuration set-
              ting.  Otherwise, a domain name matches itself  and
              its subdomains.

           Note 1: the special pattern * represents any address (i.e.
           it functions as the wild-card pattern).

           Note 2:  the  null  recipient  address  is  looked  up  as
           $empty_address_recipient@$myhostname (default: mailer-dae-
           mon@hostname).

       'Nexthop'      => '',
           This field has the format transport:nexthop and shows how
           the mails for the corresponding destination will be
	   delivered.

           The transport field specifies the name of a mail  delivery
           transport (the first name of a mail delivery service entry
           in the Postfix master.cf file).
           
           The interpretation  of  the  nexthop  field  is  transport
           dependent. In the case of SMTP, specify host:service for a
           non-default server port, and use [host] or [host]:port  in
           order  to  disable MX (mail exchanger) DNS lookups. The []
           form is required when you specify an IP address instead of
           a hostname.
           
           A  null  transport  and  null nexthop result means "do not
           change": use the delivery transport and  nexthop  informa-
           tion  that  would  be used when the entire transport table
           did not exist.
           
           A non-null transport  field  with  a  null  nexthop  field
           resets the nexthop information to the recipient domain.
           
           A  null  transport  field with non-null nexthop field does
           not modify the transport information.

	   For a detailed description have a look in man 5 trnsport.

       'TLS'          => '',
	     You can set how TLS will be used for security. Possible values are:
		NONE    : don't use TLS.
		MAY     : TLS will used when offered by the server.
		MUST    : Only connection with TLS will be accepted.
		MUST_NOPEERMATCH  : Only connection with TLS will be accepted, but
		          no strict peername checking accours.
			  
       'Auth'     => 0,
             Sets if SASL authentication will be used for the relayhost.
	     Possible values are: 0 (no) and 1 (yes).
			
       'Account'  => '',
	     The account name of the SASL account.
			
       'Password' => ''
	     The SASL account password
    );


EXAMPLE:

use MailServer;

    my $AdminPassword   = "VerySecure";

    my $MailTransorts   = [];

    if (! $MailTransorts = ReadMailTransports($AdminPassword) ) {
       print "ERROR in ReadMailTransports\n";
    } else {
       foreach my $Transport (@{$MailTransports->{'Transports'}}){
            print "Destination=> $Transport->{'Destination'}\n";
	    print "    Nexthop=> $Transport->{'Nexthop'}\n";
	    print "        TLS=> $Transport->{'TLS'}\n";
	    if( $Transport->{'Auth'} ) {
	        print "    Account=> $Transport->{'Account'}\n";
	        print "   Passpord=> $Transport->{'Password'}\n";
	    } else {
	        print "    No SASL authentication is required.\n";
	    }
       }
    }

=cut


BEGIN { $TYPEINFO{ReadMailTransports}  =["function", ["map", "string", "any"]  , "string"]; }
sub ReadMailTransports {
    my $self            = shift;
    my $AdminPassword   = shift;


    my %MailTransports  = ( 
                           'Changed' => '0',
                           'Transports'  => [] 
                          );

    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

    my %SearchMap       = (
                               'base_dn'    => $ldap_map->{'mail_config_dn'},
                               'filter'     => "ObjectClass=SuSEMailTransport",
                               'scope'      => 2,
                               'map'        => 1,
                               'attributes' => ['SuSEMailTransportDestination',
			                        'SuSEMailTransportNexthop',
						'SuSEMailTransportTLS']
                          );

    my $SaslPaswd = SCR->Read('.mail.postfix.saslpasswd.table');
                             
    # Searching all the transport lists
    my $ret = SCR->Read('.ldap.search',\%SearchMap);


    # filling up our array
    foreach my $dn (keys %{$ret}){
       my $Transport       = {};
       $Transport->{'Destination'}     = $ret->{$dn}->{'susemailtransportdestination'}->[0];
       if( $ret->{$dn}->{'susemailtransportnexthop'}->[0] =~ /:/) {
         ($Transport->{'Transport'},$Transport->{'Nexthop'}) = split /:/,$ret->{$dn}->{'susemailtransportnexthop'}->[0];
       } else {
         $Transport->{'Nexthop'}         = $ret->{$dn}->{'susemailtransportnexthop'}->[0];
       }
       $Transport->{'TLS'}             = $ret->{$dn}->{'susemailTransportls'}->[0] || "NONE";
       $Transport->{'Auth'}            = 0;
       $Transport->{'Account'}         = '';
       $Transport->{'Password'}        = '';
       #Looking the type of TSL
       my $tmp = read_attribute($SaslPaswd,$Transport->{'Destination'});
       if($tmp) {
           ($Transport->{'Account'},$Transport->{'Password'}) = split /:/, $tmp;
            $Transport->{'Auth'} = 1;
       }
       push @{$MailTransports{'Transports'}}, $Transport;
    }
    
#print STDERR Dumper(%MailTransports);

    #now we return the result
    return \%MailTransports;
}

=item *
C<boolean = WriteMailTransports($adminpwd,$MailTransports)>

 Write the mail server Mail Transport from a single hash.

 WARNING!

 All transport defintions not contained in the hash will be removed
 from the tranport table.

EXAMPLE:

use MailServer;

    my $AdminPassword   = "VerySecure";

    my %MailTransports  = ( 
                           'Changed' => '1',
                           'Transports'  => [] 
                          );
    my %Transport       = (
                             'Destination'  => 'dom.ain',
                             'Transport'    => 'smtp',
                             'Nexthop'      => '[mail.dom.ain]',
                             'TLS'          => 'MUST',
                             'Auth'         => 1,
                             'Account'      => 'user',
                             'Password'     => 'passwd'
                          );
    push @($MailTransports{Transports}), %Transport; 
    
    %Transport       = (
                             'Destination'  => 'my-domain.de',
                             'Nexthop'      => 'uucp:[mail.my-domain.de]',
                             'TLS'          => 'NONE',
                             'Auth'         => '0'
			);
    push @($MailTransports{Transports}), %Transport; 

    %Transport       = (
                             'Destination'  => 'my-old-domain.de',
                             'Nexthop'      => "error:I've droped this domain"
			);
    push @($MailTransports{Transports}), %Transport; 

    if( ! WriteMailTransports(\%Transports,$AdminPassword) ) {
        print "ERROR in WriteMailTransport\n";
    }

=cut

BEGIN { $TYPEINFO{WriteMailTransports}  =["function", "boolean", ["map", "string", "any"], "string"]; }
sub WriteMailTransports {
    my $self            = shift;
    my $MailTransports  = shift;
    my $AdminPassword   = shift;
   
    # Pointer for Error MAP
    my $ERROR = [];

    # Map for the Transport Entries
    my %Entries   = (); 
    my $ldap_map  = {}; 

    # If no changes we haven't to do anything
    if(! $MailTransports->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # We'll need the sasl passwords entries
    my $SaslPasswd = SCR->Read('.mail.postfix.saslpasswd.table');

    # Make LDAP Connection 
    $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

    # Search hash to find all the Transport Objects
    my %SearchMap       = (
                               'base_dn' => $ldap_map->{'mail_config_dn'},
                               'filter'  => "objectclass=susemailtransport",
                               'map'     => 1,
                               'scope'   => 2,
                               'attrs'   => ['susemailtransportdestination']
                          );

    # First we have to clean the corresponding SaslPasswd entries in the hash
    my $ret = SCR->Read('.ldap.search',\%SearchMap);
    foreach my $key (keys %{$ret}){    
       write_attribute($SaslPasswd,$ret->{$key}->{'susemailtransportdestination'},'');
    }

    # Now let's work
    foreach my $Transport (@{$MailTransports->{'Transports'}}){
       if( $Transport->{'Destination'} =~ /[^\w\*\.\@]/ ) {
            $ERROR->{'summary'} = _("Wrong Value for Mail Transport Destination. ").
	                          _('This field may contain only the charaters [a-zA-Z.*@]');
            $ERROR->{'code'}    = "PARAM_CHECK_FAILED";
            return $self->SetError( $ERROR );
      }
       my $dn	= 'SuSEMailTransportDestination='.$Transport->{'Destination'}.','.$ldap_map->{'mail_config_dn'};
       $Entries{$dn}->{'SuSEMailTransportDestination'}   = $Transport->{'Destination'};
       if(defined $Transport->{'Transport'} ) {
          $Entries{$dn}->{'SuSEMailTransportNexthop'}       = $Transport->{'Transport'}.':'.$Transport->{'Nexthop'};
       } else {
          $Entries{$dn}->{'SuSEMailTransportNexthop'}       = $Transport->{'Nexthop'};
       }
       $Entries{$dn}->{'SuSEMailTransportTLS'}           = 'NONE';
       if($Transport->{'Auth'}) {
               # If needed write the sasl auth account & password
               write_attribute($SaslPasswd,$Transport->{'Destination'},"$Transport->{'Account'}:$Transport->{'Password'}");
       }
       if($Transport->{'TLS'} =~ /NONE|MAY|MUST|MUST_NOPEERMATCH/) {
            $Entries{$dn}->{'SuSEMailTransportTLS'}      = $Transport->{'TLS'};
       } else {
            $ERROR->{'summary'} = _("Wrong Value for MailTransportTLS");
            $ERROR->{'code'}    = "PARAM_CHECK_FAILED";
            return $self->SetError( $ERROR );
       }
    }
#print STDERR Dumper(%Entries);

    #have a look if our table is OK. If not make it to work!
    my $MainCf             = SCR->Read('.mail.postfix.main.table');
    check_ldap_configuration('transport',$ldap_map);
    write_attribute($MainCf,'transport_maps','ldap:/etc/postfix/ldaptransport.cf');
    check_ldap_configuration('tls_per_site',$ldap_map);
    write_attribute($MainCf,'smtp_tls_per_site','ldap:/etc/postfix/ldapsmtp_tls_per_site.cf');

    # If there is no ERROR we do the changes
    # First we clean all the transport lists
    foreach my $key (keys %{$ret}){
       if(! SCR->Write('.ldap.delete',{'dn'=>$key})){
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary     => "LDAP delete failed",
                                 code        => "SCR_WRITE_FAILED",
                                 description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }

    foreach my $dn (keys %Entries){
       my $DN  = { 'dn' => $dn };
       my $tmp = { 'Objectclass'                  => [ 'SuSEMailTransport' ],
                   'SuSEMailTransportDestination' => $Entries{$dn}->{'SuSEMailTransportDestination'},
                   'SuSEMailTransportNexthop'     => $Entries{$dn}->{'SuSEMailTransportNexthop'},
                   'SuSEMailTransportTLS'         => $Entries{$dn}->{'SuSEMailTransportTLS'}
                 };
       if(! SCR->Write('.ldap.add',$DN,$tmp)){
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary     => "LDAP add failed",
                                 code        => "SCR_WRITE_FAILED",
                                 description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }
    SCR->Write('.mail.postfix.saslpasswd.table',$SaslPasswd);

    return 1;
}

=item *
C<$MailPrevention = ReadMailPrevention($adminpwd)>

 Dump the mail-server prevention to a single hash
 @return hash Dumped settings (later acceptable by WriteMailPrevention())

 Postfix offers a variety of parameters that limit the delivery of 
 unsolicited commercial email (UCE). 

 By default, the Postfix SMTP server will accept mail only from or to the
 local network or domain, or to domains that are hosted by Postfix, so that
 your system can't be used as a mail relay to forward bulk mail from random strangers.

 There is a lot of combination of the postfix configuration parameter 
 you can set. To make the setup easier we have defined three kind of predefined
 settings: 
   off:
        1. Accept connections from all clients even if the client IP address has no 
           PTR (address to name) record in the DNS. 
        2. Accept all eMails has RCPT a local destination or the client is in the
           local network.
        3. Mail adresses via access table can be rejected.
   medium:
        1. Accept connections from all clients even if the client IP address has no 
           PTR (address to name) record in the DNS. 
        2. Accept all eMails has RCPT a local destination and the sender domain is
           a valid domain. Furthermore mails from clients from local network will
           be accepted.
        3. 
   hard:

 $MailPrevention is a pointer to a hash containing the mail server
 basic prevention settings. This hash has following structure:


 my %MailPrevention      = (
           'Changed'               => 0,
             Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

           'BasicProtection'       => 'hard',
           'RBLList'               => [],
           'AccessList'            => [],
           'VirusScanning'         => 1
                          );

   AccessList is a pointer to an array of %AccessEntry hashes.

 my %AccessEntry         = (  'ClientAddress' => '',
                              'ClientAccess'  => ''
			   );

EXAMPLE:

use MailServer;

    my $AdminPassword   = "VerySecure";
    my $MailPrevention  = [];

    if( $MailPrevention = ReadMailPrevention($AdminPassword) ) {
        print "Basic BasicProtection : $MailPrevention->{BasicProtection}\n";
        foreach(@{$MailPrevention->{RBLList}}) {
          print "Used RBL Server: $_\n";
        }
        foreach(@{$MailPrevention->{AccessList}}) {
          print "Access for  $_{MailClient} is $_{MailAction}\n";
        }
        if($MailPrevention->{VirusScanning}){
          print "Virus scanning is activated\n";
        } else {
          print "Virus scanning isn't activated\n";
        }
    } else {
        print "ERROR in ReadMailPrevention\n";
    }

=cut

BEGIN { $TYPEINFO{ReadMailPrevention}  =["function", "any", "string" ]; }
sub ReadMailPrevention {
    my $self            = shift;
    my $AdminPassword   = shift;

    my %MailPrevention  = (
                               'Changed'                    => 0,
			       'BasicProtection'            => 'hard',
			       'RBLList'                    => [],
			       'AccessList'                 => [],
			       'VirusScanning'              => 1
                          );

    my $ERROR        = '';

    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

    # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    # We ar looking for the BasicProtection Basic Prevention
    my $smtpd_helo_restrictions = read_attribute($MainCf,'smtpd_helo_restrictions');
    if( $smtpd_helo_restrictions !~ /reject_invalid_hostname/ ) {
       my $smtpd_helo_required  = read_attribute($MainCf,'smtpd_helo_required');
       if( $smtpd_helo_required =~ /no/ ) {
         $MailPrevention{'BasicProtection'} =  'off';    
       } else {
         $MailPrevention{'BasicProtection'} =  'medium';
       }
    }

    # If the BasicProtection Basic Prevention is not off we collect the list of the RBL hosts
    if($MailPrevention{'BasicProtection'} ne 'off') {
       my $smtpd_client_restrictions = read_attribute($MainCf,'smtpd_client_restrictions');
       foreach(split /, |,/, $smtpd_client_restrictions){
          if(/reject_rbl_client (.*)/){
	    push @{$MailPrevention{'RBLList'}}, $1;
	  }
       }
    }

    #Now we read the access table
    my %SearchMap = (
                   'base_dn' => $ldap_map->{'mail_config_dn'},
                   'filter'  => "ObjectClass=SuSEMailAccess",
                   'scope'   => 2,
                   'attrs'   => ['SuSEMailClient','SuSEMailAction']
                 );
    my $ret = SCR->Read('.ldap.search',\%SearchMap);
    foreach my $entry (@{$ret}){  
       my $AccessEntry = {};
       $AccessEntry->{'MailClient'} = $entry->{'susemailclient'}->[0];
       $AccessEntry->{'MailAction'} = $entry->{'susemailaction'}->[0];
       push @{$MailPrevention{'AccessList'}}, $AccessEntry;
    }
    
    return \%MailPrevention;
}

##
 # Write the mail-server Mail Prevention from a single hash
 #
BEGIN { $TYPEINFO{WriteMailPrevention}  =["function", "boolean", ["map", "string", "any"], "string"]; }
sub WriteMailPrevention {
    my $self            = shift;
    my $MailPrevention  = shift;
    my $AdminPassword   = shift;

    my $ERROR  = '';

    if(! $MailPrevention->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
   
    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

    # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    #Collect the RBL host list
    my $clnt_restrictions = '';
    foreach(@{$MailPrevention->{'RBLList'}}){
      if($clnt_restrictions eq '') {
          $clnt_restrictions="reject_rbl_client $_";
      } else {
          $clnt_restrictions="$clnt_restrictions, reject_rbl_client $_";
      }
    }

    if($MailPrevention->{'BasicProtection'} eq 'hard') {
      #Write hard settings 
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:/etc/postfix/ldapacess.cf, reject_unknown_sender_domain');   
       write_attribute($MainCf,'smtpd_helo_required','yes');   
       write_attribute($MainCf,'smtpd_helo_restrictions','permit_mynetworks, reject_invalid_hostname');   
       write_attribute($MainCf,'strict_rfc821_envelopes','yes');   
       write_attribute($MainCf,'smtpd_recipient_restrictions','permit_mynetworks, reject_unauth_destination');
       if( $clnt_restrictions ne '') {
          write_attribute($MainCf,'smtpd_client_restrictions',"permit_mynetworks, $clnt_restrictions, reject_unknown_client");
       }  else {
          write_attribute($MainCf,'smtpd_client_restrictions','permit_mynetworks, reject_unknown_client');
       }
    } elsif($MailPrevention->{'BasicProtection'} eq 'medium') {
      #Write medium settings  
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:/etc/postfix/ldapacess.cf, reject_unknown_sender_domain');   
       write_attribute($MainCf,'smtpd_helo_required','yes');   
       write_attribute($MainCf,'smtpd_helo_restrictions','');   
       write_attribute($MainCf,'strict_rfc821_envelopes','no');   
       write_attribute($MainCf,'smtpd_recipient_restrictions','permit_mynetworks, reject_unauth_destination');
       if( $clnt_restrictions ne '') {
          write_attribute($MainCf,'smtpd_client_restrictions',"$clnt_restrictions");
       }  else {
          write_attribute($MainCf,'smtpd_client_restrictions','');
       }
    } elsif($MailPrevention->{'BasicProtection'} eq 'off') {
      # Write off settings  
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:/etc/postfix/ldapacess.cf');   
       write_attribute($MainCf,'smtpd_helo_required','no');   
       write_attribute($MainCf,'smtpd_helo_restrictions','');   
       write_attribute($MainCf,'strict_rfc821_envelopes','no');   
       write_attribute($MainCf,'smtpd_recipient_restrictions','permit_mynetworks, reject_unauth_destination');
       write_attribute($MainCf,'smtpd_client_restrictions','');
    } else {
      # Error no such value
         return $self->SetError( summary =>_("Unknown BasicProtection mode. Allowed values are: hard, medium, off"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    #Now we have a look on the access table
    my %SearchMap = (
                   'base_dn' => $ldap_map->{'mail_config_dn'},
                   'filter'  => "ObjectClass=SuSEMailAccess",
                   'scope'   => 2,
                   'map'     => 1
                 );
    my $ret = SCR->Read('.ldap.search',\%SearchMap);
    #First we clean the access table
    foreach my $key (keys %{$ret}){
       if(! SCR->Write('.ldap.delete',{'dn'=>$key})){
          my $ldapERR = SCR->Read(".ldap.error");
          return $self->SetError(summary     => "LDAP delete failed",
                                 code        => "SCR_WRITE_FAILED",
                                 description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }

    #Now we write the new table
#print STDERR Dumper([$MailPrevention->{'AccessList'}]);
    foreach my $entry (@{$MailPrevention->{'AccessList'}}) {
       my $dn  = { 'dn' => "SuSEMailClient=".$entry->{'MailClient'}.','. $ldap_map->{'mail_config_dn'}};
       my $tmp = { 'SuSEMailClient'   => $entry->{'MailClient'},
                   'SuSEMailAction'   => $entry->{'MailAction'},
                   'ObjectClass'      => ['SuSEMailAccess']
                 };
       if(! SCR->Write('.ldap.add',$dn,$tmp)){
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP add failed",
                               code => "SCR_INIT_FAILED",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
       }
    }

    # now we looks if the ldap entries in the main.cf for the access table are OK.
    check_ldap_configuration('access',$ldap_map);
    SCR->Write('.mail.postfix.main.table',$MainCf);

    return  1;
}

=item *
C<$MailRelaying = ReadMailRelaying($adminpwd)>

 Dump the mail-server server side relay settings to a single hash
 @return hash Dumped settings (later acceptable by WriteMailRelaying ())

 $MailRelaying is a pointer to a hash containing the mail server
 relay settings. This hash has following structure:

 %MailRelaying    = (
           'Changed'               => 0,
             Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

           'TrustedNetworks' => [],
             An array of trusted networks/hosts addresses

           'RequireSASL'     => 1,
             Show if SASL authentication is required for sending external eMails.
 
           'SMTPDTLSMode'    => 'use',
             Shows how TLS will be used for smtpd connection.
             Avaiable values are:
             'none'      : no TLS will be used.
             'use'       : TLS will be used if the client wants.
             'enfoce'    : TLS must be used.
             'auth_only' : TLS will be used only for SASL authentication.

           'UserRestriction' => 0
             If UserRestriction is set, there is possible to make user/group based 
             restrictions for sending and getting eMails. Strickt authotentication
             is requiered. To do so an 2nd interface for sending eMails for internal
             clients will be set up. The system administrator have to care that the
             other interface (external interface) can not be accessed from the internal
             clients
                          );

  

=cut

BEGIN { $TYPEINFO{ReadMailRelaying}  =["function", "any", "string" ]; }
sub ReadMailRelaying {
    my $self            = shift;
    my $AdminPassword   = shift;
    my %MailRelaying    = (
                                'Changed'         => 0,
                                'TrustedNetworks' => [],
                                'RequireSASL'     => 0,
                                'SMTPDTLSMode'    => 'use',
                                'UserRestriction' => 0
                          );

    my $ERROR  = '';

    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

    # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    # Now we look if there are manual inclued mynetworks entries
    # my $TrustedNetworks    = read_attribute($MainCf,'mynetworks');
    my $TrustedNetworks = `postconf -h mynetworks`;
    chomp $TrustedNetworks;
    foreach(split /, |,| /, $TrustedNetworks) { 
       if(! /ldapmynetworks/ && /\w+/) {
          push @{$MailRelaying{'TrustedNetworks'}}, $_;
       }
    }

    #Now we have a look on the mynetworks ldaptable
#    my %SearchMap = (
##                   'base_dn' => $ldap_map->{'mail_config_dn'},
#                   'filter'  => "ObjectClass=SuSEMailMyNetorks",
#                   'attrs'   => ['SuSEMailClient']
#                 );
#    my $ret = SCR->Read('.ldap.search',\%SearchMap);
#
#    foreach my $entry (@{$ret}){
#        foreach(@{$entry->{'SuSEMailClient'}}) {
#          push @{$MailRelaying{'TrustedNetworks'}}, $_;
#        }
#    }

    my $smtpd_recipient_restrictions = read_attribute($MainCf,'smtpd_recipient_restrictions');
    my $smtpd_sasl_auth_enable       = read_attribute($MainCf,'smtpd_sasl_auth_enable');
    my $smtpd_use_tls                = read_attribute($MainCf,'smtpd_use_tls');
    my $smtpd_enforce_tls            = read_attribute($MainCf,'smtpd_enforce_tls');
    my $smtpd_tls_auth_only          = read_attribute($MainCf,'smtpd_tls_auth_only');
    if($smtpd_use_tls eq 'no') {
       $MailRelaying{'SMTPDTLSMode'} = 'none';
    }
    if($smtpd_enforce_tls eq 'yes') {
       $MailRelaying{'SMTPDTLSMode'} = 'enforce';
    }
    if($smtpd_tls_auth_only eq 'yes') {
       $MailRelaying{'SMTPDTLSMode'} = 'auth_only';
    } 
    if($smtpd_sasl_auth_enable eq 'yes') {
       $MailRelaying{'RequireSASL'}  = 1;
       if( $smtpd_recipient_restrictions !~ /permit_sasl_authenticated/) {
         return $self->SetError( summary => _('Postfix configuration misteak: smtpd_sasl_auth_enable set yes,').
                                            _('but smtpd_recipient_restrictions dose not contain permit_sasl_authenticated.'),
                                 code    => "PARAM_CHECK_FAILED" );
       }                          
    }

#print STDERR Dumper(%MailRelaying);
    return \%MailRelaying;
}

##
 # Write the mail-server server side relay settings  from a single hash
 #
BEGIN { $TYPEINFO{WriteMailRelaying}  =["function", "boolean",["map", "string", "any"], "string"]; }
sub WriteMailRelaying {
    my $self            = shift;
    my $MailRelaying    = shift;
    my $AdminPassword   = shift;
   
    my $ERROR = '';

    #If nothing to do we don't do antithing
    if(! $MailRelaying->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

#print STDERR Dumper(%{$MailRelaying});
   # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    # now we collent the trusted networks;
    my $TrustedNetworks    = '';
    foreach(@{$MailRelaying->{'TrustedNetworks'}}){
      if( $TrustedNetworks ne '' ) {
        $TrustedNetworks = $TrustedNetworks.', '.$_
      } else {
        $TrustedNetworks = $_;
      }
    }
    write_attribute($MainCf,'mynetworks',$TrustedNetworks);

    #now we write TLS settings for the smtpd daemon
    if($MailRelaying->{'SMTPDTLSMode'} eq 'none') {
        write_attribute($MainCf,'smtpd_use_tls','no');
        write_attribute($MainCf,'smtp_enforce_tls','no');
        write_attribute($MainCf,'smtpd_tls_auth_only','no');
    } elsif($MailRelaying->{'SMTPDTLSMode'} eq 'use') {
        write_attribute($MainCf,'smtpd_use_tls','yes');
        write_attribute($MainCf,'smtp_enforce_tls','no');
        write_attribute($MainCf,'smtpd_tls_auth_only','no');
    } elsif($MailRelaying->{'SMTPDTLSMode'} eq 'enforce') {
        write_attribute($MainCf,'smtpd_use_tls','yes');
        write_attribute($MainCf,'smtp_enforce_tls','yes');
        write_attribute($MainCf,'smtpd_tls_auth_only','no');
    } elsif($MailRelaying->{'SMTPDTLSMode'} eq 'auth_only') {
        write_attribute($MainCf,'smtpd_use_tls','yes');
        write_attribute($MainCf,'smtp_enforce_tls','no');
        write_attribute($MainCf,'smtpd_tls_auth_only','yes');
    } else {
         return $self->SetError( summary => _('Bad value for SMTPDTLSMode. Avaiable values are:').
                                            "\nnone use enforce auth_only",
                                 code    => "PARAM_CHECK_FAILED" );
    }

    SCR->Write('.mail.postfix.main.table',$MainCf);

    return 1;

}

##
BEGIN { $TYPEINFO{ReadMailLocalDelivery}  =["function", "any", "string"]; }
sub ReadMailLocalDelivery {
    my $self            = shift;
    my $AdminPassword   = shift;
    my %MailLocalDelivery = (
                                'Changed'         => 0,
                                'Type'            => '',
                                'MailboxSize'     => '',
                                'FallBackMailbox' => '',
                                'SpoolDirectory'  => '',
                                'QuotaLimit'      => '',
                                'HardQuotaLimit'  => '',
                                'ImapIdleTime'    => '',
                                'PopIdleTime'     => '',
                                'AlternativNameSpace'  => ''
                            );

    my $ERROR;

    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

   # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');

    my $MailboxCommand     = read_attribute($MainCf,'mailbox_command');
    my $MailboxTransport   = read_attribute($MainCf,'mailbox_transport');
    my $MailboxSizeLimit   = read_attribute($MainCf,'mailbox_size_limit');
    my $HomeMailbox        = read_attribute($MainCf,'home_mailbox');
    my $MailSpoolDirectory = read_attribute($MainCf,'mail_spool_directory');
    my $LocalTransport     = read_attribute($MainCf,'local_transport');

    if($MailboxTransport eq 'local' || ( $MailboxCommand eq '' && $MailboxTransport eq '')) {
       $MailLocalDelivery{'Type'}      = 'local';
       if( $MailboxSizeLimit =~ /^\d+$/ ) {
            $MailLocalDelivery{'MailboxSize'}  = $MailboxSizeLimit;
       } 
       if( $HomeMailbox ne '' ) {
           $MailLocalDelivery{'SpoolDirectory'} = '$HOME/'.$HomeMailbox;
       } elsif ( $MailSpoolDirectory ne '' ) {
           $MailLocalDelivery{'SpoolDirectory'} = $MailSpoolDirectory;
       } else {
           $MailLocalDelivery{'SpoolDirectory'} = '/var/spool/mail';
       }
    } elsif($MailboxCommand =~ /\/usr\/bin\/procmail/) {
        $MailLocalDelivery{'Type'} = 'procmail';
    } elsif($MailboxTransport =~ /lmtp:unix:public\/lmtp/) {
        $MailLocalDelivery{'Type'} = 'cyrus';
        $MailLocalDelivery{'MailboxSizeLimit'}         = SCR->Read('.etc.imapd_conf.autocreatequota') || 0;
        $MailLocalDelivery{'QuotaLimit'}               = SCR->Read('.etc.imapd_conf.quotawarn') || 0;
        $MailLocalDelivery{'ImapIdleTime'}             = SCR->Read('.etc.imapd_conf.timeout') || 0;
        $MailLocalDelivery{'PopIdleTime'}              = SCR->Read('.etc.imapd_conf.poptimeout') || 0;
        $MailLocalDelivery{'FallBackMailbox'}          = SCR->Read('.etc.imapd_conf.lmtp_luser_relay') || '';
        if(  SCR->Read('.etc.imapd_conf.altnamespace') eq 'yes' ) {
            $MailLocalDelivery{'AlternateNameSpace'}   = 1; 
        } else {
            $MailLocalDelivery{'AlternateNameSpace'}   = 0; 
        }
        if(  SCR->Read('.etc.imapd_conf.lmtp_overquota_perm_failure') eq 'yes' ) {
            $MailLocalDelivery{'HardQuotaLimit'}       = 1; 
        } else {
            $MailLocalDelivery{'HardQuotaLimit'}       = 0; 
        }
    } else {
        $MailLocalDelivery{'Type'} = 'none';
    }
    return \%MailLocalDelivery;
}


BEGIN { $TYPEINFO{WriteMailLocalDelivery}  =["function", "boolean",["map", "string", "any"], "string"]; }
sub WriteMailLocalDelivery {
    my $self              = shift;
    my $MailLocalDelivery = shift;
    my $AdminPassword     = shift;

    my $ERROR;

    #If nothing to do we don't do antithing
    if(! $MailLocalDelivery->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

    # First we read the main.cf
    my $MainCf             = SCR->Read('.mail.postfix.main.table');
#print STDERR Dumper([$MailLocalDelivery]);   
    if(      $MailLocalDelivery->{'Type'} eq 'local') {
	write_attribute($MainCf,'mailbox_command','');
	write_attribute($MainCf,'mailbox_transport','local');
	if($MailLocalDelivery->{'MailboxSizeLimit'} =~ /^\d+$/) {
	     write_attribute($MainCf,'mailbox_size_limit',$MailLocalDelivery->{'MailboxSizeLimit'});     
	} else {
            return $self->SetError( summary => _('Maximum Mailbox Size value may only contain decimal number in byte'),
                                      code    => "PARAM_CHECK_FAILED" );
	}
	if($MailLocalDelivery->{'SpoolDirectory'} =~ /\$HOME\/(.*)/) {
	   write_attribute($MainCf,'home_mailbox',$1);
	   write_attribute($MainCf,'mail_spool_directory','');
	} elsif(-e $MailLocalDelivery->{'SpoolDirectory'}) {
	   write_attribute($MainCf,'home_mailbox','');
	   write_attribute($MainCf,'mail_spool_directory',$MailLocalDelivery->{'SpoolDirectory'});
	} else {
            return $self->SetError( summary => _('Bad value for SpoolDirectory. Possible values are:').
	                                       _('"$HOME/<path>" or a path to an existing directory.'),
                                      code  => "PARAM_CHECK_FAILED" );
	}
    } elsif( $MailLocalDelivery->{'Type'} eq 'procmail') {
        write_attribute($MainCf,'home_mailbox','');     
	write_attribute($MainCf,'mail_spool_directory','');
	write_attribute($MainCf,'mailbox_command','/usr/bin/procmail');
	write_attribute($MainCf,'mailbox_transport','');
    } elsif( $MailLocalDelivery->{'Type'} eq 'cyrus') {
        write_attribute($MainCf,'home_mailbox','');
	write_attribute($MainCf,'mail_spool_directory','');
	write_attribute($MainCf,'mailbox_command','');
	write_attribute($MainCf,'mailbox_transport','lmtp:unix:public/lmtp'); 
        SCR->Write('.etc.imapd_conf.autocreatequota',$MailLocalDelivery->{'MailboxSizeLimit'});
        SCR->Write('.etc.imapd_conf.quotawarn',$MailLocalDelivery->{'QuotaLimit'});
        SCR->Write('.etc.imapd_conf.timeout',$MailLocalDelivery->{'ImapIdleTime'});
        SCR->Write('.etc.imapd_conf.poptimeout',$MailLocalDelivery->{'PopIdleTime'});
        SCR->Write('.etc.imapd_conf.lmtp_luser_relay',$MailLocalDelivery->{'FallBackMailbox'});
        if( $MailLocalDelivery->{'AlternateNameSpace'} ) {
	    SCR->Write('.etc.imapd_conf.altnamespace','yes');
	} else {
	    SCR->Write('.etc.imapd_conf.altnamespace','no');
	}
        if( $MailLocalDelivery->{'HardQuotaLimit'} ) {
	    SCR->Write('.etc.imapd_conf.lmtp_overquota_perm_failure','yes');
        } else {
	    SCR->Write('.etc.imapd_conf.lmtp_overquota_perm_failure','no');
        }
    } else {
        return $self->SetError( summary => _('Bad value for MailLocalDeliveryType. Possible values are:').
                                           _('"local", "procmail" or "cyrus".'),
                                  code  => "PARAM_CHECK_FAILED" );
    }

    SCR->Write('.mail.postfix.main.table',$MainCf);
    SCR->Write('.etc.imapd_conf',undef);
    return 1;
}

BEGIN { $TYPEINFO{ReadFetchingMail}     =["function", "any", "string"]; }
sub ReadFetchingMail {
    my $self            = shift;
    my $AdminPassword   = shift;

    my %FetchingMail = (
                                'FetchByDialIn'   => 1,
                                'FetchMailSteady' => 1,
                                'FetchingInterval'=> 30,
				'Items'           => []     
				
                       );
    my $CronTab        = SCR->Read('.cron','/etc/crontab',\%FetchingMail);

    if(! Service->Enabled('fetchmail')) {
        $FetchingMail{'FetchMailSteady'} = 0;
    }

    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

    $FetchingMail{'Items'} = SCR->Read('.mail.fetchmail.accounts');
    
#print STDERR Dumper(%FetchingMail);    

    return \%FetchingMail;
}

BEGIN { $TYPEINFO{WriteFetchingMail}    =["function", "boolean", ["map", "string", "any"], "string"]; }
sub WriteFetchingMail {
    my $self            = shift;
    my $FetchingMail    = shift;
    my $AdminPassword   = shift;

    #If nothing to do we don't do antithing
    if(! $FetchingMail->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }

#print STDERR Dumper([$FetchingMail]);    

    SCR->Write('.mail.fetchmail.accounts',$FetchingMail->{'Items'});
    SCR->Write('.mail.fetchmail',undef);
    return 1;
}

BEGIN { $TYPEINFO{ReadMailLocalDomains}  =["function", "any", "string"]; }
sub ReadMailLocalDomains {
    my $self             = shift;
    my $AdminPassword    = shift;
    my %MailLocalDomains = (
                                'Changed'         => 0,
                                'Domains'         => []
                           );

    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }
    my $ret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldap_map->{'dns_config_dn'},
                                          "filter"       => '(objectclass=suseMailDomain)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'ou', 'SuSEMailDomainMasquerading', 'SuSEMailDomainType' ]
                                         });
    if (! defined $ret) {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    foreach(@{$ret}) {
       my $domain = {};
       $domain->{'Name'}        = $_->{'ou'}->[0];
       $domain->{'Type'}        = $_->{'SuSEMailDomainType'}->[0]         || 'local';
       $domain->{'Masqueradin'} = $_->{'SuSEMailDomainMasquerading'}->[0] || 'yes';
       push @{$MailLocalDomains{'Domains'}}, $domain;
    }
    return \%MailLocalDomains;
}

BEGIN { $TYPEINFO{WriteMailLocalDomains} =["function", "boolean", ["map", "string", "any"], "string"]; }
sub WriteMailLocalDomains {
    my $self             = shift;
    my $MailLocalDomains = shift;
    my $AdminPassword    = shift;

    my $Domains          = {};

    #If nothing to do we don't do antithing
    if(! $MailLocalDomains->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Make LDAP Connection 
    my $ldap_map = $self->ReadLDAPDefaults($AdminPassword);
    if( !$ldap_map ) {
         return undef;
    }
    foreach(@{$MailLocalDomains->{'Domains'}}){
      my $name          = $_->{'Name'};
      my $type          = $_->{'Type'} || 'local';
      my $masquerading  = $_->{'Masquerading'} || 'yes';
      if( $name !~ /^(\w+\.\w+)+$/) {
         return $self->SetError( summary =>_("Invalid domain name.").
	                                   " Domain: $name".
                                 code    => "PARAM_CHECK_FAILED" );
      }
      if($type !~ /local|virtual|main/) {
         return $self->SetError( summary =>_("Invalid mail local domain type.").
	                                   " Domain: $name; Type $type".
					   _("Allowed values are: local|virtual|main."),
                                 code    => "PARAM_CHECK_FAILED" );
      }
      if($masquerading !~ /yes|no/) {
         return $self->SetError( summary =>_("Invalid mail local domain masquerading value.").
	                                   " Domain: $name; Masquerading: $masquerading".
					   _("Allowed values are: yes|no."),
                                 code    => "PARAM_CHECK_FAILED" );
      }
      my $DN = "ou=$name,$ldap_map->{'dns_config_dn'}";
      $Domains->{$DN}->{'ou'}                         = $name;
      $Domains->{$DN}->{'SuSEMailDomainType'}         = $type;
      $Domains->{$DN}->{'SuSEMailDomainMasquerading'} = $masquerading;
    }
    foreach my $DN (keys %{$Domains}) {
      if( SCR->Read('.ldap.search',{
                                          "base_dn"      => $DN,
                                          "filter"       => '(objectclass=suseMailDomain)',
                                          "scope"        => 0,
                                          "not_found_ok" => 0
                                         } ) ) {
         if( ! SCR->Write('ldap.modify',{ "dn" => $DN } , $Domains->{$DN})) {
            my $ldapERR = SCR->Read(".ldap.error");
            return $self->SetError(summary => "LDAP add failed",
                               code => "SCR_INIT_FAILED",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
         }
      } else {
         $Domains->{$DN}->{'objectclass'}  = ['SUSEMailDomain','OrganizationalUnit'];
         if( ! SCR->Write('.ldap.add',{ "dn" => $DN } , $Domains->{$DN})) {
            my $ldapERR = SCR->Read(".ldap.error");
            return $self->SetError(summary => "LDAP add failed",
                               code => "SCR_INIT_FAILED",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
         }
      }
    }

    return 1;
}


BEGIN { $TYPEINFO{ReadLDAPDefaults} = ["function", ["map", "string", "any"], "string"]; }
sub ReadLDAPDefaults {
    my $self          = shift;
    my $AdminPassword = shift;

    my $ldapMap       = {};
    my $admin_bind    = {};
    my $ldapret       = undef;
    my $ERROR; 


    if(Ldap->Read()) {
        $ldapMap = Ldap->Export();
        if(defined $ldapMap->{'ldap_server'} && $ldapMap->{'ldap_server'} ne "") {
            my $dummy = $ldapMap->{'ldap_server'};
            $ldapMap->{'ldap_server'} = Ldap->GetFirstServer("$dummy");
            $ldapMap->{'ldap_port'} = Ldap->GetFirstPort("$dummy");
        } else {
            return $self->SetError( summary => "No LDAP Server configured",
                                    code => "HOST_NOT_FOUND");
        }
    }
#print STDERR Dumper([$ldapMap]);

    if (! SCR->Execute(".ldap", {"hostname" => $ldapMap->{'ldap_server'},
                                 "port"     => $ldapMap->{'ldap_port'}})) {
        return $self->SetError(summary => "LDAP init failed",
                               code => "SCR_INIT_FAILED");
    }

    # anonymous bind
    if (! SCR->Execute(".ldap.bind", {}) ) {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP bind failed",
                               code => "SCR_INIT_FAILED",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'});
    }

    # searching LDAP Bases
    # First we search mail base
    $ldapret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'base_config_dn'},
                                          "filter"       => '(objectclass=suseMailServerConfiguration)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'suseDefaultBase' ]
                                         });
    if (! defined $ldapret) {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret > 0) {
        $ldapMap->{'mail_config_dn'} = $ldapret->[0]->{'susedefaultbase'}->[0];
    }
    # now we search user base
    $ldapret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'base_config_dn'},
                                          "filter"       => '(objectclass=suseUserConfiguration)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'suseDefaultBase' ]
                                         });
    if (! defined $ldapret) {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret > 0) {
        $ldapMap->{'user_config_dn'} = $ldapret->[0]->{'susedefaultbase'}->[0];
    }
    # now we search group base
    $ldapret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'base_config_dn'},
                                          "filter"       => '(objectclass=suseGroupConfiguration)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'suseDefaultBase' ]
                                         });
    if (! defined $ldapret) {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret > 0) {
        $ldapMap->{'group_config_dn'} = $ldapret->[0]->{'susedefaultbase'}->[0];
    }
    # now we search DNS base
    $ldapret = SCR->Read(".ldap.search", {
                                          "base_dn"      => $ldapMap->{'base_config_dn'},
                                          "filter"       => '(objectclass=suseDNSConfiguration)',
                                          "scope"        => 2,
                                          "not_found_ok" => 1,
                                          "attrs"        => [ 'suseDefaultBase' ]
                                         });
    if (! defined $ldapret) {
        my $ldapERR = SCR->Read(".ldap.error");
        return $self->SetError(summary => "LDAP search failed!",
                               description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                               code => "LDAP_SEARCH_FAILED");
    }
    if(@$ldapret > 0) {
        $ldapMap->{'dns_config_dn'} = $ldapret->[0]->{'susedefaultbase'}->[0];
    }

    # Now we try to bind to the LDAP
    if (! SCR->Execute(".ldap", {"hostname" => $ldapMap->{'ldap_server'},
                                 "port"     => $ldapMap->{'ldap_port'}})) {
        return $self->SetError(summary => "LDAP init failed",
                               code => "SCR_INIT_FAILED");
    }

    $ldapMap->{'bind_pw'} = $AdminPassword;
#    $admin_bind->{'bind_dn'} = $ldapMap->{'bind_dn'};
#    $admin_bind->{'bind_pw'} = $AdminPassword;
    if(! SCR->Execute('.ldap.bind',$ldapMap)) {
         my $ldapERR = SCR->Read('.ldap.error');
         return $self->SetError(summary     => "LDAP bind failed!",
                                description => $ldapERR->{'code'}." : ".$ldapERR->{'msg'},
                                code        => "LDAP_BIND_FAILED");
    }
    

    return $ldapMap;
}
##
 # Create a textual summary and a list of unconfigured cards
 # @return summary of the current configuration
 #
BEGIN { $TYPEINFO{Summary} = ["function", [ "list", "string" ] ]; }
sub Summary {
    # TODO FIXME: your code here...
    # Configuration summary text for autoyast
    return (
        _("Configuration summary ...")
    );
}

##
 # Create an overview table with all configured cards
 # @return table items
 #
BEGIN { $TYPEINFO{Overview} = ["function", [ "list", "string" ] ]; }
sub Overview {
    # TODO FIXME: your code here...
    return ();
}

##
 # Return packages needed to be installed and removed during
 # Autoinstallation to insure module has all needed software
 # installed.
 # @return hash with 2 lists.
 #
BEGIN { $TYPEINFO{AutoPackages} = ["function", ["map", "string", ["list", "string"]]]; }
sub AutoPackages {
    # TODO FIXME: your code here...
    my %ret = (
        "install" => (),
        "remove" => (),
    );
    return \%ret;
}


# some helper funktions
sub read_attribute {
    my $config    = shift;
    my $attribute = shift;

    foreach(@{$config}){
        if($_->{"key"} eq $attribute) {
                return $_->{"value"};
        }
    }
    return '';
}

sub write_attribute {
    my $config    = shift;
    my $attribute = shift;
    my $value     = shift;
    my $comment   = shift;

    my $unset = 1;

    foreach(@{$config}){
        if($_->{"key"} eq $attribute) {
            $_->{"value"} = $value;
            $unset = 0; 
            last;
        }
    }
    if($unset) {
        push (@{$config}, { "comment" => $comment,
                                "key" => $attribute,
                              "value" => $value }
                  );
    }
    return 1;
}

# Internal helper Funktion to check if a needed ldap table is correctly defined
# in the main.cf. If not so the neccesary entries will be created.
sub check_ldap_configuration {
    my $config      = shift;
    my $ldap_map    = shift;

    my $changes   = 0;
    my %query_filter     = (
                        'transport' => '(&(objectclass=SuSEMailTransport)(SuSEMailTransportDestination=%s))',
                        'smtp_tls_per_site' => '(&(objectclass=SuSEMailTransport)(SuSEMailTransportDestination=%s))',
                        'peertls'   => '(&(objectclass=SuSEMailTransport)(SuSEMailTransportDestination=%s))',
                        'access'    => '(&(objectclass=SuSEMailAccess)(SuSEMailClient=%s))',
                        'mynetworks'=> '(&(objectclass=SuSEMailMyNetworks)(SuSEMailClient=%s))'
                       );
    my %result_attribute = (
                        'transport' => 'SuSEMailTransportNexthop',
                        'smtp_tls_per_site' => 'SuSEMailTransportTLS',
                        'peertls'   => 'SuSEMailTransportTLS',
                        'access'    => 'SuSEMailAction',
                        'mynetworks'=> 'SuSEMailClient'
                       );
    my %scope            = (
                        'transport' => 'one',
                        'smtp_tls_per_site' => 'one',
                        'peertls'   => 'one',
                        'access'    => 'one',
                        'mynetworks'=> 'one'
                       );

    #First we read the whool main.cf configuration
    my $LDAPCF    = SCR->Read('.mail.ldaptable',$config);

    #Now we are looking for if all the needed ldap entries are done
    if(!$LDAPCF->{'server_host'} || $LDAPCF->{'server_host'} ne $ldap_map->{'ldap_server'}) {
         $LDAPCF->{'server_host'} = $ldap_map->{'ldap_server'};
	 $changes = 1;
    }
    if(! $LDAPCF->{'server_port'} || $LDAPCF->{'server_port'} ne $ldap_map->{'ldap_port'}) {
         $LDAPCF->{'server_port'} = $ldap_map->{'ldap_port'};
	 $changes = 1;
    }
    if(! $LDAPCF->{'bind'}  || $LDAPCF->{'bind'} ne 'no') {
         $LDAPCF->{'bind'} = 'no';
	 $changes = 1;
    }
    if(! $LDAPCF->{'timeout'} || $LDAPCF->{'timeout'} !~ /^\d+$/){
         $LDAPCF->{'bind'} = '20';
	 $changes = 1;
    }
    if(! $LDAPCF->{'search_base'} || $LDAPCF->{'search_base'} ne $ldap_map->{'mail_config_dn'}) {
         $LDAPCF->{'search_base'} = $ldap_map->{'mail_config_dn'}; 
	 $changes = 1;
    }
    if(! $LDAPCF->{'query_filter'} || $LDAPCF->{'query_filter'} ne $query_filter{$config}) {
         $LDAPCF->{'query_filter'} = $query_filter{$config}; 
	 $changes = 1;
    }
    if(! $LDAPCF->{'result_attribute'} || $LDAPCF->{'result_attribute'} ne $result_attribute{$config}) {
         $LDAPCF->{'result_attribute'} = $result_attribute{$config}; 
	 $changes = 1;
    }
    if(! $LDAPCF->{'result_attribute'} || $LDAPCF->{'scope'} ne $scope{$config}) {
         $LDAPCF->{'scope'} = $scope{$config}; 
	 $changes = 1;
    }

    # If we had made changes we have to save it
    if($changes) {
       SCR->Write('.mail.ldaptable',[$config,$LDAPCF]);
    }

    return $changes;
}

1;

# EOF
