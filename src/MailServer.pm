#! /usr/bin/perl -w
# File:		modules/MailServer.pm
# Package:	Configuration of mail-server
# Summary:	MailServer settings, input and output functions
# Authors:	Peter Varkoly <varkoly@suse.de>
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

setlocale(LC_MESSAGES, "");
textdomain("mail-server");
our %TYPEINFO;

YaST::YCP::Import ("SCR");
YaST::YCP::Import ("Service");


sub _ {
    return gettext($_[0]);
}
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
BEGIN { $TYPEINFO{ReadGlobalSettings}  =["function", "any"  ]; }
sub ReadGlobalSettings {
    my $MainCf    = SCR::Read('.mail.postfix.main.table');
    my $SaslPaswd = SCR::Read('.mail.postfix.saslpasswd.table');
    my %GlobalSettings = ( 
    			   'Changed' => 'false',
    			   'MSize'   => 0,
    			   'Relay'   => { 
			   		'Type'      => '',
			   		'Security'  => '',
					'RHost'     => {
							 'Name'     => '',
							 'Security' => '',
							 'Auth'     => 0,
							 'Account'  => '',
							 'Password' => ''
						       },
			   		
			   	      },
			 );
    # Reading maximal size of transported messages
    
    
    $GlobalSettings{'MSize'}                  = read_attribute($MainCf,'message_size_limit');

    # Determine if relay host is used
    $GlobalSettings{'Relay'}{'RHost'}{'Name'} = read_attribute($MainCf,'relayhost');

    if($GlobalSettings{'Relay'}{'RHost'}{'Name'} ne '') {
      # If relay host is used read & set some parameters
    	$GlobalSettings{'Relay'}{'Type'} = 'relayhost';
	
        # Determine if relay host need sasl authentication
	my $tmp = read_attribute($SaslPaswd,$GlobalSettings{'Relay'}{'RHost'}{'Name'}); 
        if( $tmp ) {
                ($GlobalSettings{'Relay'}{'RHost'}{'Account'},$GlobalSettings{'Relay'}{'RHost'}{'Password'}) = split /:/,$tmp;
        }
        if($GlobalSettings{'Relay'}{'RHost'}{'Account'}  ne '') {
           $GlobalSettings{'Relay'}{'RHost'}{'Auth'} = 1;
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
    my $self = shift;
    my $GlobalSettings = shift;
    my $MSize          = $GlobalSettings->{'MSize'};
    my $RelayTyp       = $GlobalSettings->{'Relay'}{'Type'};
    my $RHostName      = $GlobalSettings->{'Relay'}{'RHost'}{'Name'};
    my $RHostSecurity  = $GlobalSettings->{'Relay'}{'RHost'}{'Security'};
    my $RHostAuth      = $GlobalSettings->{'Relay'}{'RHost'}{'Auth'};
    my $RHostAccount   = $GlobalSettings->{'Relay'}{'RHost'}{'Account'};
    my $RHostPassword  = $GlobalSettings->{'Relay'}{'RHost'}{'Password'};
    my $MainCf         = SCR::Read('.mail.postfix.main.table');
    my $SaslPasswd     = SCR::Read('.mail.postfix.saslpasswd.table');
    
    # Parsing attributes 
    if($MSize =~ /[^\d+]/) {
         return $self->SetError( summary =>_("Mail size value may only contain decimal number in byte"),
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
        write_attribute($MainCf,'relayhost',$RHostName);
        if($RHostAuth){
           write_attribute($SaslPasswd,$RHostName,"$RHostAccount:$RHostPassword");
        }
    } else {
      return $self->SetError( summary =>_("Unknown mail sending type. Allowed values are 'DNS' & 'relayhost'"),
                              code    => "PARAM_CHECK_FAILED" );
      return 0;
    }

    write_attribute($MainCf,'message_size_limit',$MSize);

    SCR::Write('.mail.postfix.main.table',$MainCf);
    SCR::Write('.mail.postfix.saslpasswd.table',$SaslPasswd);

    Service::Reload('postfix');
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
