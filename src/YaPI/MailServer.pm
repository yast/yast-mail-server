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




package MailServer;

use strict;

use ycp;
use YaST::YCP;
use YaPI;

use Locale::gettext;
use POSIX;     # Needed for setlocale()
use Data::Dumper;

setlocale(LC_MESSAGES, "");
textdomain("mail-server");
our %TYPEINFO;
our @CAPABILITIES = (
                     'SLES9'
                    );

YaST::YCP::Import ("SCR");
YaST::YCP::Import ("Service");


#sub _ {
#    return gettext($_[0]);
#}

# -------------- Global Variable -------------------
my $dns_basedn   = '';
my $mail_basedn  = '';
my $user_basedn  = '';
my $group_basedn = '';
my $ldapserver   = '';
my $ldapport     = '';
my $ldapadmin    = '';
my $my_ldap      = [];
my $admin_bind   = [];
# -------------------------------------------------

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
    my $MasterCf  = SCR::Read('.mail.postfix.mastercf');

    return $MasterCf;
}

BEGIN { $TYPEINFO{findService}  =["function", "any"  ]; }
sub findService {
    my ($service, $command ) = @_;

    my $services  = SCR::Read('.mail.postfix.mastercf.findService', $service, $command);

    return $services;
}
=item *
C<$GlobalSettings = ReadGlobalSettings($AdminDN,$AdminPassword)>

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

    my $AdminDN         = "uid=admin,ou=users,dc=my-company,dc=org";
    my $AdminPassword   = "VerySecure";


=cut

BEGIN { $TYPEINFO{ReadGlobalSettings}  =["function", ["map", "string", "any" ], "string", "string" ]; }
sub ReadGlobalSettings {
    my $self            = shift;
    my $AdminDN         = shift;
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

    my $MainCf    = SCR::Read('.mail.postfix.main.table');
    my $SaslPaswd = SCR::Read('.mail.postfix.saslpasswd.table');
    if( ! SCR::Read('.mail.postfix.master') ) {
         return $self->SetError( summary =>_("Couln't open master.cf"),
                                 code    => "PARAM_CHECK_FAILED" );
    }

    # Reading maximal size of transported messages
    $GlobalSettings{'MaximumMailSize'}           = read_attribute($MainCf,'message_size_limit');

    #
    $GlobalSettings{'Banner'}                    = read_attribute($MainCf,'smtpd_banner');

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
	my $smtpsrv = SCR::Execute('.mail.postfix.master.findService',
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

    my $AdminDN         = "uid=admin,ou=users,dc=my-company,dc=org";
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

   if( ! WriteGlobalSettings(\%GlobalSettings,$AdminDN,$AdminPassword) ) {
        print "ERROR in WriteGlobalSettings\n";
   }

=cut

BEGIN { $TYPEINFO{WriteGlobalSettings}  =["function", "boolean",  ["map", "string", "any" ], "string", "string" ]; }
sub WriteGlobalSettings {
    my $self               = shift;
    my $GlobalSettings     = shift;
    my $AdminDN            = shift;
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
    my $MainCf             = SCR::Read('.mail.postfix.main.table');
    my $SaslPasswd         = SCR::Read('.mail.postfix.saslpasswd.table');
    if( ! SCR::Read('.mail.postfix.master') ) {
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
       my $smtpsrv = SCR::Execute('.mail.postfix.master.findService',
                   { 'service' => 'smtp',
                     'command' => 'smtp' });
       if(! defined $smtpsrv ) {
           SCR::Execute('.mail.postfix.master.deleteService', { 'service' => 'smtp', 'command' => 'smtp' });
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
	SCR::Execute('.mail.postfix.master.deleteService', { 'service' => 'smtp', 'command' => 'smtp' });
    } else {
      return $self->SetError( summary =>_("Unknown mail sending type. Allowed values are:").
                                          " NONE | DNS | relayhost",
                              code    => "PARAM_CHECK_FAILED" );
    }
    #Now we write TLS settings if needed
    if($SendingMailType ne 'NONE'){
       if($SendingMailTLS eq 'NONE') {
         write_attribute($MainCf,'smtp_use_tls','no');
         write_attribute($MainCf,'smtp_enforce_tls','');
         write_attribute($MainCf,'smtp_tls_enforce_peername','');
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
    }

    write_attribute($MainCf,'message_size_limit',$MaximumMailSize);
    write_attribute($MainCf,'smtpd_banner',$GlobalSettings->{'Banner'});

    SCR::Write('.mail.postfix.main.table',$MainCf);
    SCR::Write('.mail.postfix.saslpasswd.table',$SaslPasswd);

    return 1;
}

=item *
C<$MailTransports = ReadMailTransports($AdminDN,$AdminPassword)>

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

    my $AdminDN         = "uid=admin,ou=users,dc=my-company,dc=org";
    my $AdminPassword   = "VerySecure";

    my $MailTransorts   = [];

    if (! $MailTransorts = ReadMailTransports($AdminDN,$AdminPassword) ) {
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


BEGIN { $TYPEINFO{ReadMailTransports}  =["function", ["map", "string", "any"]  , "string", "string" ]; }
sub ReadMailTransports {
    my $self            = shift;
    my $AdminDN         = shift;
    my $AdminPassword   = shift;


    my %MailTransports  = ( 
                           'Changed' => '0',
                           'Transports'  => [] 
                          );
    my %Transport       = (
                             'Destination'  => '',
                             'Nexthop'      => '',
                             'TLS'          => '',
                             'Auth'         => '',
                             'Account'      => '',
                             'Password'     => ''
                          );
    my %SearchMap       = (
                               'base_dn'    => $mail_basedn,
                               'filter'     => "ObjectClass=SuSEMailTransport",
                               'attributes' => ['SuSEMailTransportDestination',
			                        'SuSEMailTransportNexthop',
						'SuSEMailTransportTLS']
                          );

    my $SaslPaswd = SCR::Read('.mail.postfix.saslpasswd.table');
                             
    # Anonymous bind 
    SCR::Execute('.ldap');
    SCR::Execute('.ldap.bind');

    # Searching all the transport lists
    my $ret = SCR::Read('.ldap.search',\%SearchMap);

    # filling up our array
    foreach(@{$ret}){
       $Transport{'Destination'}     = $_->{'SuSEMailTransportDestination'};
       $Transport{'Nexthop'}         = $_->{'SuSEMailTransportNexthop'};
       $Transport{'TLS'}             = $_->{'SuSEMailTransporTLS'};
       $Transport{'Auth'}            = 0;
       $Transport{'Account'}         = '';
       $Transport{'Password'}        = '';
       #Looking the type of TSL
       my $tmp = read_attribute($SaslPaswd,$Transport{'Destination'});
       if($tmp) {
           ($Transport{'Account'},$Transport{'Password'}) = split /:/, $tmp;
            $Transport{'Auth'} = 1;
       }
       push @{$MailTransports{'Transports'}}, %Transport;
    }
    

    #now we return the result
    return \%MailTransports;
}

=item *
C<boolean = WriteMailTransports($admindn,$adminpwd,$MailTransports)>

 Write the mail server Mail Transport from a single hash.

 WARNING!

 All transport defintions not contained in the hash will be removed
 from the tranport table.

EXAMPLE:

use MailServer;

    my $AdminDN         = "uid=admin,ou=users,dc=my-company,dc=org";
    my $AdminPassword   = "VerySecure";

    my %MailTransports  = ( 
                           'Changed' => '1',
                           'Transports'  => [] 
                          );
    my %Transport       = (
                             'Destination'  => 'dom.ain',
                             'Nexthop'      => 'mail.dom.ain',
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

    if( ! WriteMailTransports(\%Transports,$AdminDN,$AdminPassword) ) {
        print "ERROR in WriteMailTransport\n";
    }

=cut

BEGIN { $TYPEINFO{WriteMailTransports}  =["function", "boolean", ["map", "string", "any"], "string", "string" ]; }
sub WriteMailTransports {
    my $self            = shift;
    my $MailTransports  = shift;
    my $AdminDN         = shift;
    my $AdminPassword   = shift;
    
    # Pointer for Error MAP
    my $ERROR = [];

    # Array for the Transport Entries
    my @Entries   = '';

    # If no changes we haven't to do anything
    if(! $MailTransports->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Search hash to find all the Transport Objects
    my %SearchMap       = (
                               'base_dn' => $mail_basedn,
                               'filter'  => "ObjectClass=SuSEMailTransport",
                               'attrs'   => ['SuSEMailTransportDestination']
                          );

    # We'll need the sasl passwords entries
    my $SaslPasswd = SCR::Read('.mail.postfix.saslpasswd.table');

    # Make LDAP Connection 
    my $ErrorSummary = read_ldap_settings();
    if( $ErrorSummary  ne '' ) {
         return $self->SetError( summary => $ErrorSummary,
                                 code    => "PARAM_CHECK_FAILED" );
    }
    if($AdminDN) {
        $admin_bind->{'binddn'} = $AdminDN;
    }
    if($AdminPassword) {
        $admin_bind->{'bindpw'} = $AdminPassword;
    }
    if(! SCR::Execute('.ldap',$my_ldap)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }
    if(! SCR::Execute('.ldap.bind',$admin_bind)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }

    # First we have to clean the corresponding SaslPasswd entries in the hash
    my $ret = SCR::Read('.ldap.search',\%SearchMap);
    foreach my $entry (@{$ret}){    
       write_attribute($SaslPasswd,$entry->{'SuSEMailTransportDestination'},'');
    }

    # Now let's work
    foreach my $Transport (@{$MailTransports->{'Transports'}}){
       my %entry = ();
       if( $Transport->{'Destination'} =~ /[^\w\*\.\@]/ ) {
            $ERROR->{'summary'} = _("Wrong Value for Mail Transport Destination. ").
	                          _('This field may contain only the charaters [a-zA-Z.*@]');
            $ERROR->{'code'}    = "PARAM_CHECK_FAILED";
            return $self->SetError( $ERROR );
	       }
       $entry{'dn'}  				= 'SuSEMailTransportDestination='.$Transport->{'Destination'}.','.$mail_basedn;
       $entry{'SuSEMailTransportDestination'}   = $Transport->{'Destination'};
       $entry{'SuSEMailTransportNexthop'}       = $Transport->{'Nexthop'};
       $entry{'SuSEMailTransportTLS'}           = 'NONE';
       if($Transport->{'Auth'}) {
               # If needed write the sasl auth account & password
               write_attribute($SaslPasswd,$Transport->{'Destination'},"$Transport->{'Account'}:$Transport->{'Password'}");
       }
       if($Transport->{'TLS'} =~ /NONE|MAY|MUST|MUST_NOPEERMATCH/) {
            $entry{'SuSEMailTransportTLS'}      = $Transport->{'TLS'};
       } else {
            $ERROR->{'summary'} = _("Wrong Value for MailTransportTLS");
            $ERROR->{'code'}    = "PARAM_CHECK_FAILED";
            return $self->SetError( $ERROR );
       }
       push @Entries, %entry;
    }

    #have a look if our table is OK. If not make it to work!
    check_ldap_configuration('transport');

    # If there is no ERROR we do the changes
    # First we clean all the transport lists
    $ret = SCR::Read('.ldap.search',\%SearchMap);
    foreach my $entry (@{$ret}){    
       SCR::Write('.ldap.delete',['dn'=>$entry->{'dn'}]);
    }

    foreach my $entry (@Entries){
       my $dn  = [ 'dn' => $entry->{'dn'} ];
       my $tmp = [ 'SuSEMailTransportDestination' => $entry->{'SuSEMailTransportDestination'},
                   'SuSEMailTransportNexthop'     => $entry->{'SuSEMailTransportNexthop'},
                   'SuSEMailTransportTLS'         => $entry->{'SuSEMailTransportTLS'}
                 ];
       SCR::Execute('.ldap.add',$dn,$tmp);
    }
    SCR::Write('.mail.postfix.saslpasswd.table',$SaslPasswd);

    return 1;
}

=item *
C<$MailPrevention = ReadMailPrevention($admindn,$adminpwd)>

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

    my $AdminDN         = "uid=admin,ou=users,dc=my-company,dc=org";
    my $AdminPassword   = "VerySecure";
    my $MailPrevention  = [];

    if( $MailPrevention = ReadMailPrevention($AdminDN,$AdminPassword) ) {
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

BEGIN { $TYPEINFO{ReadMailPrevention}  =["function", "any", "string", "string"  ]; }
sub ReadMailPrevention {
    my $self            = shift;
    my $AdminDN         = shift;
    my $AdminPassword   = shift;

    my %MailPrevention  = (
                               'Changed'                    => 0,
			       'BasicProtection'            => 'hard',
			       'RBLList'                    => [],
			       'AccessList'                 => [],
			       'VirusScanning'              => 1
                          );

    my %AccessEntry     = (    
                               'MailClient'  => '',
                               'MailAction'  => ''
                          );

    my $ERROR        = '';

    # Make LDAP Connection 
    my $ErrorSummary = read_ldap_settings();
    if( $ErrorSummary  ne '' ) {
         return $self->SetError( summary => $ErrorSummary,
                                 code    => "PARAM_CHECK_FAILED" );
    }
    if($AdminDN) {
        $admin_bind->{'binddn'} = $AdminDN;
    }
    if($AdminPassword) {
        $admin_bind->{'bindpw'} = $AdminPassword;
    }
    if(! SCR::Execute('.ldap',$my_ldap)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }
    if(! SCR::Execute('.ldap.bind',$admin_bind)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }

    # First we read the main.cf
    my $MainCf             = SCR::Read('.mail.postfix.main.table');

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
          if(/reject_rbl_client (\w+)/){
	    push @{$MailPrevention{'RBLList'}}, $1;
	  }
       }
    }

    #Now we read the access table
    my %SearchMap = (
                   'base_dn' => $mail_basedn,
                   'filter'  => "ObjectClass=SuSEMailAccess",
                   'attrs'   => ['SuSEMailClient','SuSEMailAction']
                 );
    my $ret = SCR::Read('.ldap.search',\%SearchMap);
    foreach my $entry (@{$ret}){    
       $AccessEntry{'MailClient'} = $entry->{'SuSEMailClient'};
       $AccessEntry{'MailAccess'} = $entry->{'SuSEMailAction'};
       push @{$MailPrevention{'AccessList'}}, %AccessEntry;
    }
    
    return \%MailPrevention;
}

##
 # Write the mail-server Mail Prevention from a single hash
 #
BEGIN { $TYPEINFO{WriteMailPrevention}  =["function", "boolean", "string", "string", ["map", "string", "any"] ]; }
sub WriteMailPrevention {
    my $self            = shift;
    my $AdminDN         = shift;
    my $AdminPassword   = shift;
    my $MailPrevention  = shift;

    my $ERROR  = '';

    if(! $MailPrevention->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
   
    # Make LDAP Connection 
    my $ErrorSummary = read_ldap_settings();
    if( $ErrorSummary  ne '' ) {
         return $self->SetError( summary => $ErrorSummary,
                                 code    => "PARAM_CHECK_FAILED" );
    }
    if($AdminDN) {
        $admin_bind->{'binddn'} = $AdminDN;
    }
    if($AdminPassword) {
        $admin_bind->{'bindpw'} = $AdminPassword;
    }
    if(! SCR::Execute('.ldap',$my_ldap)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }
    if(! SCR::Execute('.ldap.bind',$admin_bind)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }

    # First we read the main.cf
    my $MainCf             = SCR::Read('.mail.postfix.main.table');

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
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:ldapacess, reject_unknown_sender_domain');   
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
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:ldapacess, reject_unknown_sender_domain');   
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
       write_attribute($MainCf,'smtpd_sender_restrictions','ldap:ldapacess');   
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
                   'base_dn' => $mail_basedn,
                   'filter'  => "ObjectClass=SuSEMailAccess",
                   'attrs'   => []
                 );
    my $ret = SCR::Read('.ldap.search',\%SearchMap);
    #First we clean the access table
    foreach my $entry (@{$ret}){    
       SCR::Write('.ldap.delete',['dn'=>$entry->{'dn'}]);
    }
    #Now we write the new table
    foreach my $entry (@{$MailPrevention->{'AccessList'}}) {
       my $dn  = [ 'dn' => "SuSEMailClient=".$entry->{'SuSEMailClient'}.','. $mail_basedn];
       my $tmp = [ 'SuSEMailClient'   => $entry->{'MailClient'},
                   'SuSEMailAction'   => $entry->{'SuSEMailAction'}
                 ];
       SCR::Execute('.ldap.add',$dn,$tmp);
    }

    # now we looks if the ldap entries in the main.cf for the access table are OK.
    check_ldap_configuration('access');
}

=item *
C<$MailRelaying = ReadMailRelaying($admindn,$adminpwd)>

 Dump the mail-server server side relay settings to a single hash
 @return hash Dumped settings (later acceptable by WriteMailRelaying ())

 $MailRelaying is a pointer to a hash containing the mail server
 relay settings. This hash has following structure:

 %MailRelaying    = (
           'Changed'               => 0,
             Shows if the hash was changed. Possible values are 0 (no) or 1 (yes).

           'TrustedNetworks' => [''],
             An array of trusted networks/hosts addresses

           'RequireSASL'     => 1,
             Show if SASL authotentication is required for sending external eMails.
 
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

BEGIN { $TYPEINFO{ReadMailRelaying}  =["function", "any", "string", "string"  ]; }
sub ReadMailRelaying {
    my $self            = shift;
    my $AdminDN         = shift;
    my $AdminPassword   = shift;
    my %MailRelaying    = (
                                'Changed'         => 0,
                                'TrustedNetworks' => [''],
                                'RequireSASL'     => 1,
                                'SMTPDTLSMode'    => 'use',
                                'UserRestriction' => 0
                          );

    my $ERROR  = '';

    # Make LDAP Connection 
    my $ErrorSummary = read_ldap_settings();
    if( $ErrorSummary  ne '' ) {
         return $self->SetError( summary => $ErrorSummary,
                                 code    => "PARAM_CHECK_FAILED" );
    }
    if($AdminDN) {
        $admin_bind->{'binddn'} = $AdminDN;
    }
    if($AdminPassword) {
        $admin_bind->{'bindpw'} = $AdminPassword;
    }
    if(! SCR::Execute('.ldap',$my_ldap)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }
    if(! SCR::Execute('.ldap.bind',$admin_bind)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }

    # First we read the main.cf
    my $MainCf             = SCR::Read('.mail.postfix.main.table');

    # Now we look if there are manual inclued mynetworks entries
    my $TrustedNetworks    = read_attributes($MainCf,'mynetworks');
    foreach(split /, |,/, $TrustedNetworks) { 
       if(! /ldapmynetworks/) {
          push @{$MailRelaying{'TrustedNetworks'}}, $_;
       }
    }

    #Now we have a look on the mynetworks ldaptable
#    my %SearchMap = (
##                   'base_dn' => $mail_basedn,
#                   'filter'  => "ObjectClass=SuSEMailMyNetorks",
#                   'attrs'   => ['SuSEMailClient']
#                 );
#    my $ret = SCR::Read('.ldap.search',\%SearchMap);
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
    if($smtpd_enforce_tls eq 'on') {
       $MailRelaying{'SMTPDTLSMode'} = 'enforce';
    }
    if($smtpd_tls_auth_only eq 'on') {
       $MailRelaying{'SMTPDTLSMode'} = 'auth_only';
    } 
    if($smtpd_sasl_auth_enable eq 'on') {
       $MailRelaying{'RequireSASL'}  = 1;
       if( $smtpd_recipient_restrictions !~ /permit_sasl_authenticated/) {
         return $self->SetError( summary => _('Postfix configuration misteak: smtpd_sasl_auth_enable set yes,').
                                            _('but smtpd_recipient_restrictions dose not contain permit_sasl_authenticated.'),
                                 code    => "PARAM_CHECK_FAILED" );
       }                          
    }

    return \%MailRelaying;
}

##
 # Write the mail-server server side relay settings  from a single hash
 #
BEGIN { $TYPEINFO{WriteMailRelaying}  =["function", "boolean", "string", "string", ["map", "string", "any"] ]; }
sub WriteMailRelaying {
    my $self            = shift;
    my $AdminDN         = shift;
    my $AdminPassword   = shift;
    my $MailRelaying    = shift;
   
    my $ERROR = '';

    #If nothing to do we don't do antithing
    if(! $MailRelaying->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Make LDAP Connection 
    my $ErrorSummary = read_ldap_settings();
    if( $ErrorSummary  ne '' ) {
         return $self->SetError( summary => $ErrorSummary,
                                 code    => "PARAM_CHECK_FAILED" );
    }
    if($AdminDN) {
        $admin_bind->{'binddn'} = $AdminDN;
    }
    if($AdminPassword) {
        $admin_bind->{'bindpw'} = $AdminPassword;
    }
    if(! SCR::Execute('.ldap',$my_ldap)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }
    if(! SCR::Execute('.ldap.bind',$admin_bind)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }

    # First we read the main.cf
    my $MainCf             = SCR::Read('.mail.postfix.main.table');

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

    SCR::Write('.mail.postfix.main.table',$MainCf);

    return 1;

}

##
BEGIN { $TYPEINFO{ReadMailLocalDelivery}  =["function", "any", "string", "string"  ]; }
sub ReadMailLocalDelivery {
    my $self            = shift;
    my $AdminDN         = shift;
    my $AdminPassword   = shift;
    my %MailLocalDelivery = (
                                'Changed'         => 0,
                                'Type'            => '',
                                'MailboxSize'     => '',
                                'FallBackUser'    => '',
                                'SpoolDirectory'  => '',
                                'QuotaLimit'      => '',
                                'HardQuotaLimit'  => '',
                                'ImapIdleTime'    => '',
                                'PopIdleTime'     => '',
                                'AlternativNameSpace'  => ''
                            );

    my $ERROR;

    # Make LDAP Connection 
    my $ErrorSummary = read_ldap_settings();
    if( $ErrorSummary  ne '' ) {
         return $self->SetError( summary => $ErrorSummary,
                                 code    => "PARAM_CHECK_FAILED" );
    }
    if($AdminDN) {
        $admin_bind->{'binddn'} = $AdminDN;
    }
    if($AdminPassword) {
        $admin_bind->{'bindpw'} = $AdminPassword;
    }
    if(! SCR::Execute('.ldap',$my_ldap)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }
    if(! SCR::Execute('.ldap.bind',$admin_bind)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }

    # First we read the main.cf
    my $MainCf             = SCR::Read('.mail.postfix.main.table');

    my $MailboxCommand     = read_attribute($MainCf,'mailbox_command');
    my $MailboxTransport   = read_attribute($MainCf,'mailbox_transport');
    my $MailboxSizeLimit   = read_attribute($MainCf,'mailbox_size_limit');
    my $HomeMailbox        = read_attribute($MainCf,'home_mailbox');
    my $MailSpoolDirectory = read_attribute($MainCf,'mail_spool_directory');
    my $MaximumMailboxSize = read_attribute($MainCf,'mailbox_size_limit');
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
           $MailLocalDelivery{'SpoolDirectory'} = 'default';
       }
    } elsif($MailboxCommand =~ /\/usr\/bin\/procmail/) {
        $MailLocalDelivery{'Type'} = 'procmail';
    } elsif($MailboxTransport =~ /lmtp:unix:\/var\/lib\/imap\/socket\/lmtp/) {
        $MailLocalDelivery{'Type'} = 'cyrus';
        $MailLocalDelivery{'MailboxSizeLimit'}         = SCR::Read('.etc.imapd_conf.autocreatequota');
        $MailLocalDelivery{'QuotaLimit'}               = SCR::Read('.etc.imapd_conf.quotawarn');
        $MailLocalDelivery{'ImapIdleTime'}             = SCR::Read('.etc.imapd_conf.timeout');
        $MailLocalDelivery{'PopIdleTime'}              = SCR::Read('.etc.imapd_conf.poptimeout');
        if(  SCR::Read('.etc.imapd_conf.altnamespace') eq 'yes' ) {
            $MailLocalDelivery{'AlternateNameSpace'}   = 1; 
        } else {
            $MailLocalDelivery{'AlternateNameSpace'}   = 0; 
        }
        if(  SCR::Read('.etc.imapd_conf.lmtp_overquota_perm_failure') eq 'yes' ) {
            $MailLocalDelivery{'HardQuotaLimit'}       = 1; 
        } else {
            $MailLocalDelivery{'HardQuotaLimit'}       = 0; 
        }
    }
    return \%MailLocalDelivery;
}


BEGIN { $TYPEINFO{WriteMailLocalDelivery}  =["function", "boolean", "string", "string", ["map", "string", "any"] ]; }
sub WriteMailLocalDelivery {
    my $self              = shift;
    my $AdminDN           = shift;
    my $AdminPassword     = shift;
    my $MailLocalDelivery = shift;

    my $ERROR;

    #If nothing to do we don't do antithing
    if(! $MailLocalDelivery->{'Changed'}){
         return $self->SetError( summary =>_("Nothing to do"),
                                 code    => "PARAM_CHECK_FAILED" );
    }
    
    # Make LDAP Connection 
    my $ErrorSummary = read_ldap_settings();
    if( $ErrorSummary  ne '' ) {
         return $self->SetError( summary => $ErrorSummary,
                                 code    => "PARAM_CHECK_FAILED" );
    }
    if($AdminDN) {
        $admin_bind->{'binddn'} = $AdminDN;
    }
    if($AdminPassword) {
        $admin_bind->{'bindpw'} = $AdminPassword;
    }
    if(! SCR::Execute('.ldap',$my_ldap)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }
    if(! SCR::Execute('.ldap.bind',$admin_bind)) {
         $ERROR = SCR::Read('.ldap.error');
         return $self->SetError( $ERROR );
    }

    # First we read the main.cf
    my $MainCf             = SCR::Read('.mail.postfix.main.table');
   
    if(      $MailLocalDelivery->{'Type'} eq 'local') {
	write_attribute($MainCf,'mailbox_command','');
	write_attribute($MainCf,'mailbox_transport','local');
	if($MailLocalDelivery->{'MaximumMailboxSize'} =~ /^\d+$/) {
	     write_attribute($MainCf,'mailbox_size_limit',$MailLocalDelivery->{'MaximumMailboxSize'});     
	} else {
            return $self->SetError( summary => _('Maximum Mailbox Size value may only contain decimal number in byte'),
                                      code    => "PARAM_CHECK_FAILED" );
	}
        if(     $MailLocalDelivery->{'SpoolDirectory'} eq 'default') {
	   write_attribute($MainCf,'home_mailbox','');     
	   write_attribute($MainCf,'mail_spool_directory','');
	} elsif($MailLocalDelivery->{'SpoolDirectory'} =~ /\$HOME\/(.*)/) {
	   write_attribute($MainCf,'home_mailbox',$1);
	   write_attribute($MainCf,'mail_spool_directory','');
	} elsif(-e $MailLocalDelivery->{'SpoolDirectory'}) {
	   write_attribute($MainCf,'home_mailbox','');
	   write_attribute($MainCf,'mail_spool_directory',$MailLocalDelivery->{'SpoolDirectory'});
	} else {
            return $self->SetError( summary => _('Bad value for SpoolDirectory. Possible values are:').
	                                       _('"default", "$HOME/<path>" or a path to an existing directory.'),
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
        SCR::Write('.etc.imapd_conf.autocreatequota',$MailLocalDelivery->{'MailboxSizeLimit'});
        SCR::Write('.etc.imapd_conf.quotawarn',$MailLocalDelivery->{'QuotaLimit'});
        SCR::Write('.etc.imapd_conf.timeout',$MailLocalDelivery->{'ImapIdleTime'});
        SCR::Write('.etc.imapd_conf.poptimeout',$MailLocalDelivery->{'PopIdleTime'});
        if( $MailLocalDelivery->{'AlternateNameSpace'} ) {
	    SCR::Write('.etc.imapd_conf.altnamespace','yes');
	} else {
	    SCR::Write('.etc.imapd_conf.altnamespace','no');
	}
        if( $MailLocalDelivery->{'HardQuotaLimit'} ) {
	    SCR::Write('.etc.imapd_conf.lmtp_overquota_perm_failure','yes');
        } else {
	    SCR::Write('.etc.imapd_conf.lmtp_overquota_perm_failure','no');
        }
    } else {
        return $self->SetError( summary => _('Bad value for MailLocalDeliveryType. Possible values are:').
                                           _('"local", "procmail" or "cyrus".'),
                                  code  => "PARAM_CHECK_FAILED" );
    }

    SCR::Write('.mail.postfix.main.table',$MainCf);
    SCR::Write('.etc.imapd_conf',undef);
    return 1;
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
    my $config    = shift;
    my $changes   = 0;
    my %query_filter     = (
                        'transport' => '(&(objectclass=SuSEMailTransport)(SuSEMailTransportDestination=%s))',
                        'peertls'   => '(&(objectclass=SuSEMailTransport)(SuSEMailTransportDestination=%s))',
                        'access'    => '(&(objectclass=SuSEMailAccess)(SuSEMailClient=%s))',
                        'mynetworks'=> '(&(objectclass=SuSEMailMyNetworks)(SuSEMailClient=%s))'
                       );
    my %result_attribute = (
                        'transport' => 'SuSEMailTransportNexthop',
                        'peertls'   => 'SuSEMailTransportTLS',
                        'access'    => 'SuSEMailAction',
                        'mynetworks'=> 'SuSEMailClient'
                       );
    my %scope            = (
                        'transport' => 'one',
                        'peertls'   => 'one',
                        'access'    => 'one',
                        'mynetworks'=> 'one'
                       );

    #First we read the whool main.cf configuration
    my $MainCF    = SCR::Read('.mail.postfix.main.table');

    #Now we are looking for if all the needed ldap entries are done
    my $tmp       = read_attribute($MainCF,'ldap'.$config.'_server_host');
    if($tmp ne $ldapserver) {
         write_attribute($MainCF,'ldap'.$config.'_server_host',$ldapserver); 
	 $changes = 1;
    }
    $tmp       = read_attribute($MainCF,'ldap'.$config.'_server_port');
    if($tmp ne $ldapport) {
         write_attribute($MainCF,'ldap'.$config.'_server_port',$ldapport); 
	 $changes = 1;
    }
    $tmp       = read_attribute($MainCF,'ldap'.$config.'_bind');
    if($tmp ne 'no'){
         write_attribute($MainCF,'ldap'.$config.'_bind','no'); 
	 $changes = 1;
    }
    $tmp       = read_attribute($MainCF,'ldap'.$config.'_timeout');
    if($tmp !~ /^\d+$/){
         write_attribute($MainCF,'ldap'.$config.'_timeout',20); 
	 $changes = 1;
    }
    $tmp       = read_attribute($MainCF,'ldap'.$config.'_search_base');
    if($tmp ne $mail_basedn) {
         write_attribute($MainCF,'ldap'.$config.'_search_base',$mail_basedn); 
	 $changes = 1;
    }
    $tmp       = read_attribute($MainCF,'ldap'.$config.'_query_filter');
    if($tmp ne $query_filter{$config}) {
         write_attribute($MainCF,'ldap'.$config.'_query_filter',$query_filter{$config}); 
	 $changes = 1;
    }
    $tmp       = read_attribute($MainCF,'ldap'.$config.'_result_attribute');
    if($tmp ne $result_attribute{$config}) {
         write_attribute($MainCF,'ldap'.$config.'_result_attribute',$result_attribute{$config}); 
	 $changes = 1;
    }
    $tmp       = read_attribute($MainCF,'ldap'.$config.'_scope');
    if($tmp ne $scope{$config}) {
         write_attribute($MainCF,'ldap'.$config.'_scope',$scope{$config}); 
	 $changes = 1;
    }

    # If we had made changes we have to save it
    if($changes) {
       SCR::Write('.mail.postfix.main.table',$MainCF);
    }

    return $changes;
}

sub read_ldap_settings {
    # We have to set following global variables:
    #$dns_basedn   = '';
    #$mail_basedn  = '';
    #$user_basedn  = '';
    #$group_basedn = '';
    #$ldapserver   = '';
    #$ldapport     = '';
    #$ldapadmin    = '';
    #$my_ldap      = [];
    #$admin_bind   = [];
    $ldapserver  = SCR::Read('.etc.openldap.ldap_conf.host');
    $ldapport    = SCR::Read('.etc.openldap.ldap_conf.port');
    $mail_basedn = SCR::Read('.etc.openldap.ldap_conf.mail_basedn');
    $dns_basedn  = SCR::Read('.etc.openldap.ldap_conf.dns_basedn');
    $user_basedn = SCR::Read('.etc.openldap.ldap_conf.user_basedn');
    $group_basedn= SCR::Read('.etc.openldap.ldap_conf.group_basedn');
    if( ! $ldapserver ){
                 return _("No LDAP host");
    }
    if( ! $ldapport ){
                 return _("No LDAP host");
    }
    if( ! $mail_basedn ){
                 return _("No LDAP mail base DN");
    }
    if( ! $dns_basedn ){
                 return _("No LDAP dns base DN");
    }
    if( ! $user_basedn ){
                 return _("No LDAP user base DN");
    }
    if( ! $group_basedn ){
                 return _("No LDAP group base DN");
    }
    $my_ldap->{'host'} = $ldapserver;
    $my_ldap->{'port'} = $ldapport;
    return '';
}    
    
1;

# EOF
