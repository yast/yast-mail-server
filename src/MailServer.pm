#! /usr/bin/perl -w
# File:                modules/MailServer.pm
# Package:        Configuration of mail-server
# Summary:        MailServer settings, input and output functions
# Authors:        Peter Varkoly <varkoly@suse.de>
#
# $Id$
#
# Representation of the configuration of mail-server.
# Input and output routines.


package MailServer;

use strict;

use ycp;
use YaST::YCP;

use Locale::gettext;
use POSIX;     # Needed for setlocale()
use Data::Dumper;

setlocale(LC_MESSAGES, "");
textdomain("mail-server");
our %TYPEINFO;

YaST::YCP::Import ("SCR");
YaST::YCP::Import ("Service");


sub _ {
    return gettext($_[0]);
}

# -------------- temporary ------------------------
my $mail_basedn  = 'dc=suse,dc=de';
my $user_basedn  = 'dc=suse,dc=de';
my $group_basedn = 'dc=suse,dc=de';
my $ldapserver   = 'localhost';
my $ldapadmin    = 'root';
# -------------------------------------------------

# -------------- error handling -------------------
my %__error = ();

BEGIN { $TYPEINFO{SetError} = ["function", "boolean", ["map", "string", "any" ]]; }
sub SetError {
    my $class = shift;      # so that SetError can be called via -> like all
                            # other SCRAgent functions
    %__error = @_;
    if( !$__error{package} && !$__error{file} && !$__error{line})
    {
        @__error{'package','file','line'} = caller();
    }
    if ( defined $__error{summary} ) {
        y2error($__error{code}."[".$__error{line}.":".$__error{file}." ".$__error{summary});
    } else {
        y2error($__error{code});
    }
    return undef;
}

BEGIN { $TYPEINFO{Error} = ["function", ["map", "string", "any"] ]; }
sub Error {
    return \%__error;
}

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

##
 # Dump the mail-server Global Settings to a single map
 # @return map Dumped settings (later acceptable by WriteGlobalSettings ())
 #
BEGIN { $TYPEINFO{ReadMasterCF}  =["function", "any"  ]; }
sub ReadMasterCF {
    my $MasterCf  = SCR::Read('.mail.postfix.mastercf');

    return $MasterCf;
}

##
 # Dump the mail-server Global Settings to a single map
 # @return map Dumped settings (later acceptable by WriteGlobalSettings ())
 #
BEGIN { $TYPEINFO{findService}  =["function", "any"  ]; }
sub findService {
    my ($service, $command ) = @_;

    my $services  = SCR::Read('.mail.postfix.mastercf.findService', $service, $command);

    return $services;
}

##
 # Dump the mail-server Global Settings to a single map
 # @return map Dumped settings (later acceptable by WriteGlobalSettings ())
 #
BEGIN { $TYPEINFO{ReadGlobalSettings}  =["function", "any"  ]; }
sub ReadGlobalSettings {
    my $MainCf    = SCR::Read('.mail.postfix.main.table');
    my $SaslPaswd = SCR::Read('.mail.postfix.saslpasswd.table');
    my %GlobalSettings = ( 
                               'Changed'               => 'false',
                               'MaximumMailSize'       => 0,
                               'MaximumMailboxSize'    => 0,
                               'Relay'                 => { 
                                                        'Type'          => '',
                                                        'Security'      => '',
                                                        'RelayHost'     => {
                                                                         'Name'     => '',
                                                                         'Security' => '',
                                                                         'Auth'     => 0,
                                                                         'Account'  => '',
                                                                         'Password' => ''
                                                                       },
                                                        
                                                      },
                         );
    # Reading maximal size of transported messages
    
    
    $GlobalSettings{'MaximumMailSize'}           = read_attribute($MainCf,'message_size_limit');
    $GlobalSettings{'MaximumMailboxSize'}        = read_attribute($MainCf,'mailbox_size_limit');

    # Determine if relay host is used
    $GlobalSettings{'Relay'}{'RelayHost'}{'Name'} = read_attribute($MainCf,'relayhost');

    if($GlobalSettings{'Relay'}{'RelayHost'}{'Name'} ne '') {
      # If relay host is used read & set some parameters
            $GlobalSettings{'Relay'}{'Type'} = 'relayhost';
        
        # Determine if relay host need sasl authentication
        my $tmp = read_attribute($SaslPaswd,$GlobalSettings{'Relay'}{'RelayHost'}{'Name'}); 
        if( $tmp ) {
            ($GlobalSettings{'Relay'}{'RelayHost'}{'Account'},$GlobalSettings{'Relay'}{'RelayHost'}{'Password'}) = split /:/,$tmp;
        }
        if($GlobalSettings{'Relay'}{'RelayHost'}{'Account'}  ne '') {
           $GlobalSettings{'Relay'}{'RelayHost'}{'Auth'} = 1;
        }
    } else {
            $GlobalSettings{'Relay'}{'Type'} = 'DNS';
    }
    
    return \%GlobalSettings;
}

##
 # Write the mail-server Global Settings from a single map
 # @param settings The YCP structure to be imported.
 # @return boolean True on success
 #
BEGIN { $TYPEINFO{WriteGlobalSettings}  =["function", "boolean",  "any" ]; }
sub WriteGlobalSettings {
    my $self               = shift;
    my $GlobalSettings     = shift;

    my $MaximumMailSize    = $GlobalSettings->{'MaximumMailSize'};
    my $MaximumMailboxSize = $GlobalSettings->{'MaximumMailboxSize'};
    my $RelayTyp           = $GlobalSettings->{'Relay'}{'Type'};
    my $RelayHostName      = $GlobalSettings->{'Relay'}{'RelayHost'}{'Name'};
    my $RelayHostSecurity  = $GlobalSettings->{'Relay'}{'RelayHost'}{'Security'};
    my $RelayHostAuth      = $GlobalSettings->{'Relay'}{'RelayHost'}{'Auth'};
    my $RelayHostAccount   = $GlobalSettings->{'Relay'}{'RelayHost'}{'Account'};
    my $RelayHostPassword  = $GlobalSettings->{'Relay'}{'RelayHost'}{'Password'};
    my $MainCf             = SCR::Read('.mail.postfix.main.table');
    my $SaslPasswd         = SCR::Read('.mail.postfix.saslpasswd.table');
    
    # Parsing attributes 
    if($MaximumMailSize =~ /[^\d+]/) {
         return $self->SetError( summary =>_("Maximu Mail Size value may only contain decimal number in byte"),
                                 code    => "PARAM_CHECK_FAILED" );
         return 0;
    }
    if($MaximumMailboxSize =~ /[^\d+]/) {
         return $self->SetError( summary =>_("Maximu Mailbox Size value may only contain decimal number in byte"),
                                 code    => "PARAM_CHECK_FAILED" );
         return 0;
    }
    if($RelayTyp eq 'DNS') {
        #Make direkt mail sending
        #looking for relayhost setting from the past 
        my $tmp = read_attribute($MainCf,'relayhost');
        if( $tmp ne '' ) {
            write_attribute($MainCf,'relayhost','');
            write_attribute($SaslPasswd,$tmp,'');
        }
    } elsif ($RelayTyp eq 'relayhost') {
        write_attribute($MainCf,'relayhost',$RelayHostName);
        if($RelayHostAuth){
           write_attribute($SaslPasswd,$RelayHostName,"$RelayHostAccount:$RelayHostPassword");
        }
    } else {
      return $self->SetError( summary =>_("Unknown mail sending type. Allowed values are 'DNS' & 'relayhost'"),
                              code    => "PARAM_CHECK_FAILED" );
      return 0;
    }

    write_attribute($MainCf,'message_size_limit',$MaximumMailSize);
    write_attribute($MainCf,'mailbox_size_limit',$MaximumMailboxSize);

    SCR::Write('.mail.postfix.main.table',$MainCf);
    SCR::Write('.mail.postfix.saslpasswd.table',$SaslPasswd);

    return 1;
}

##
 # Dump the mail-server Mail Transport to a single map
 # @return map Dumped settings (later acceptable by WriteMailTransport ())
 #
BEGIN { $TYPEINFO{ReadMailTransports}  =["function", "any"  ]; }
sub ReadMailTransports {
    my $self            = shift;


    my %MailTransports  = ( 
                           'Changed' => 'false',
                           'Transports'  => [] 
                          );
    my %Transport       = (
                             'Destination'  => '',
                             'Nexthop'      => '',
                             'Security'     => '',
                             'Auth'         => '',
                             'Account'      => '',
                             'Password'     => ''
                          );
    my %SearchMap       = (
                               'base_dn' => $mail_basedn,
                               'filter'  => "ObjectClass=SuSEMailTransport"
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
       $Transport{'Security'}        = $_->{'SuSEMailTransportSecurity'};
       $Transport{'Auth'}            = $_->{'SuSEMailTransportAuth'};
       $Transport{'Account'}         = '';
       $Transport{'Password'}        = '';
       my $tmp = read_attribute($SaslPaswd,$Transport{'Destination'});
       if($tmp) {
           ($Transport{'Account'},$Transport{'Password'}) = split /:/, $tmp;
       }
       push @{$MailTransports{'Transports'}}, %Transport;
    }
    

    #now we return the result
    return \%MailTransports;
}

##
 # Write the mail-server Mail Transport from a single map
 #
BEGIN { $TYPEINFO{WriteMailTransports}  =["function", "boolean", "any"  ]; }
sub WriteMailTransports {
    my $self            = shift;
    my $MailTransports  = shift;

    my %SearchMap       = (
                               'base_dn' => $mail_basedn,
                               'filter'  => "ObjectClass=SuSEMailTransport"
                          );

    # Anonymous bind 
    SCR::Execute('.ldap');
    SCR::Execute('.ldap.bind');

    # Searching all the transport lists
    my $ret = SCR::Read('.ldap.search',\%SearchMap);
    foreach(@{$ret}){    
       SCR::Execute('.ldap.delete',$_->{'dn'});
    }

    foreach(@{$MailTransports->{'Transports'}}){
       my %entry = ();
       $entry{'dn'}  				= 'SuSEMailTransportDestination='.$_->{'Destination'}.','.$mail_basedn;
       $entry{'SuSEMailTransportDestination'}   = $_->{'Destination'};
       $entry{'SuSEMailTransportNexthop'}       = $_->{'Nexthop'};
       if($_->{'Security'} eq 'SSL' ) {
            $entry{'SuSEMailTransportSecurity'}      = $_->{'Security'};
	    my $TransportDestination = $entry{'SuSEMailTransportDestination'};
	    $TransportDestination =~ s/\.//g
	    SCR::Write('.mail.postfix.mastercf', $TransportDestination, 'smtp  -o smtpd_enforce_tls=yes');
       }
       SCR::Execute('.ldap.add',);
    }
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
 # @return map with 2 lists.
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

1;

# EOF
