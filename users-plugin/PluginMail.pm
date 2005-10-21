#! This is the API part/usr/bin/perl -w
#
# Example of plugin module
# Helper funktions for UsersPluginMail and UsersPluginMailGroups plugins 
#
require Exporter;
package PluginMail;

use strict;

use ycp;
use YaST::YCP;
use YaPI;

our %TYPEINFO;


use Net::IMAP;
use Data::Dumper;
use YaPI::MailServer;

textdomain("MailServer");

##--------------------------------------
##--------------------- global imports

YaST::YCP::Import ("SCR");

##--------------------------------------
# default object classes of LDAP mail group
my @required_object_class  = ( "SuSEMailRecipient");
    
##--------------------------------------
# error message, returned when some plugin function fails
my $error       = "";

# ----------------- Helper Funktions ----------------------
 
sub contains {
    my ( $list, $key, $ignorecase ) = @_;
    if ( $ignorecase ) {
        if ( grep /^$key$/i, @{$list} ) {
            return 1;
        }
    } else {
        if ( grep /^$key$/, @{$list} ) {
            return 1;
        }
    }
    return 0;
}

sub update_object_classes {

    my $config    = $_[0];
    my $data    = $_[1];

    # define the object class for new user/groupa
    my @orig_object_class    = ();
    if (defined $data->{"objectclass"} && ref $data->{"objectclass"} eq "ARRAY")
    {
        @orig_object_class    = @{$data->{"objectclass"}};
    }
    foreach my $oc (@required_object_class) {
        if (!contains (\@orig_object_class, $oc, 1)) {
            push @orig_object_class, $oc;
        }
    }

    $data->{"objectclass"}    = \@orig_object_class;

    return $data;
}

sub addRequiredMailData {
    my $data   = shift;
    
    if( ! contains( $data->{'objectclass'}, "susemailrecipient", 1) ) {
        push @{$data->{'objectclass'}}, "susemailrecipient";
    }
    
    return undef if !defined $data;
    return $data if !defined $data->{'cn'} || $data->{'cn'} eq "";
    
    $data->{'susemailcommand'} = '"|/usr/bin/formail -I \"From \" |/usr/lib/cyrus/bin/deliver -r '.$data->{'cn'}.' -a cyrus -m '.$data->{'cn'}.'"';

    return $data;
}

sub get_LDAP_Config {
    my $ldapMap = Ldap->Export();
    
    # Read mail specific ldapconfig object
    my $ldapret = SCR->Read(".ldap.search", {
                 "base_dn"      => $ldapMap->{'base_config_dn'},
                 "filter"       => '(objectclass=suseMailConfiguration)',
                 "scope"        => 2,
                 "not_found_ok" => 1,
                 "attrs"        => [ 'suseImapServer', 'suseImapAdmin', 'suseImapDefaultQuota' ]
            });
    if (! defined $ldapret) {
    my $ldapERR = SCR->Read(".ldap.error");
    $error = "LDAP read failed: ".$ldapERR->{'code'}." : ".$ldapERR->{'msg'};
    return undef;
    }
    return $ldapret;
}

sub cond_IMAP_OP {
    my $data   = shift;
    my $op     = shift || "add";
    my $what   = shift || "user";
    my $errtxt = "";
    my $imapadm;
    my $imaphost;
    my $uid    = $what eq "user"  ? $data->{'uid'} : ""; 
    my $fname  = $what eq "group" ? $data->{'cn'}  : "";

    if(!defined $data->{'localdeliverytype'} || $data->{'localdeliverytype'} ne 'cyrus') {
        return $data
    }
    my $ldapret = get_LDAP_Config();
    
    if(@$ldapret > 0) {
        $imapadm    = $ldapret->[0]->{'suseimapadmin'}->[0];
        $imaphost   = $ldapret->[0]->{'suseimapserver'}->[0];
        #$imapquota  = $ldapret->[0]->{'suseimapdefaultquota'}->[0];
    } else {
        $imapadm    = "cyrus";
        $imaphost   = "localhost";
        #$imapquota  = 10000;
    }
    
    # FIXME: we need to ensure, that imapadmpw == rootdnpw!
    my $imapadmpw  = Ldap->bind_pass();
    
    my $imap = new Net::IMAP($imaphost, Debug => 0);
    unless ($imap) {
        y2internal("can't connect to $imaphost: $!\n");
        $error = "can't connect to $imaphost: $!";
        return undef;
    }
    
     
    my $cpb;
    my $capaf = sub {
        my $self = shift;
        my $resp = shift;
        $cpb = $resp->{Capabilities};
    };
    
    $imap->set_untagged_callback('capability', $capaf);
    
    my $ret = $imap->capability();
    if($$ret{Status} ne "ok") {
        y2internal("capability failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        $error = "capability failed: Serverresponse:$$ret{Status} => $$ret{Text}";
        return undef;
    }
    
    if( ( ! $cpb->{QUOTA} ) || ( ! $cpb->{NAMESPACE} ) || ( ! $cpb->{ACL} ) ) {
        $error = "IMAP server <$imaphost> does not support one or all of the IMAP extensions QUOTA, NAMESPACE or ACL";
        return undef;
    }
    
    $ret = $imap->login($imapadm, $imapadmpw);
    if($$ret{Status} ne "ok") {
        y2internal("login failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        $error = "login failed: Serverresponse:$$ret{Status} => $$ret{Text}";
        return undef;
    }
  
    # What is the mailbox (folder) 
    if( $what eq 'user' ) {
        my $namespace;
        my $nscb = sub {
            my $self = shift;
            $namespace = shift;
        };
        
        $imap->set_untagged_callback('namespace', $nscb);
        
        $ret = $imap->namespace();
        if($$ret{Status} ne "ok") {
            y2internal("namespace failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
            $error = "namespace failed: Serverresponse:$$ret{Status} => $$ret{Text}";
            return undef;
        }
        
        my @users_ns = $namespace->other_users();
        
        # UGLY: Access the Namespace-Structure directly, as the access method lowercase the values
        my $hsep = $namespace->{'Namespaces'}->{'other_users'}->{$users_ns[0]};
        $fname = "user".$hsep.$uid;
    }

    if( $op eq "add" ) {
	$errtxt = create_mbox($imap,$fname,$imapadm,$what,$data);
        if( $errtxt ne "" ) {
            $error = "add failed: ".$errtxt;
            return undef;
        } elsif(  $what eq "user" ) {
           $errtxt .= subscribe_mbox($imaphost,$uid,$imapadm,$imapadmpw);
        }
    } elsif( $op eq "delete" ) {
       $ret = $imap->delete($fname);
       if($$ret{Status} ne "ok") {
           y2internal("delete failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
           $error = "delete failed: Serverresponse:$$ret{Status} => $$ret{Text}";
           return undef;
       }
    } elsif( $op eq "update" ) {
        my @__folder = ();
        # check if user's INBOX exists
        my $listcb = sub {
            my $self = shift;
            my $resp = shift;
            push @__folder, $resp->mailbox;
        };
        $imap->set_untagged_callback('list', $listcb);
        
        $ret = $imap->list("", $fname);
        
        if ($$ret{Status} ne "ok")  {
            y2internal("list failed: Serverresponse:$$ret{Status} => $$ret{Text}");
            $error = "list failed: Serverresponse:$$ret{Status} => $$ret{Text}";
            return undef;
        } else {
            if( scalar(@__folder) == 0  ) {
		$errtxt = create_mbox($imap,$fname,$what,$data);
            }
            if( $errtxt ne "" ) {
                $error = "update failed: ".$errtxt;
                return undef;
            } elsif(  $what eq "user" ) {
                $errtxt .= subscribe_mbox($imaphost,$uid,$imapadm,$imapadmpw);
            }
        }
    } elsif( $op eq "getquota" ) {
        my $q_val;
        my $q_used;
        my $qf = sub {
            my $self = shift;
            my $resp = shift;
            
            $data->{'imapquota'} = $resp->limit("STORAGE");
            $data->{'imapquotaused'} = $resp->usage("STORAGE");
        };
    
        $imap->set_untagged_callback('quota', $qf);
    
        $ret = $imap->getquotaroot($fname);
        if($$ret{Status} ne "ok") {
            y2internal("getquotaroot failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        }
    }
    
    $imap->logout();
    return $data;
}

sub create_mbox {
    my $imap    = shift; 
    my $fname   = shift; 
    my $imapadm = shift;
    my $what    = shift;
    my $data    = shift;
   
    my $errtxt;
 
    my $ret = $imap->create($fname);
    if($$ret{Status} ne "ok" && $$ret{Text} !~ /Mailbox already exists/) {
        y2internal("create failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        $errtxt .= "create failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
        #return undef;
    }
    
    $ret = $imap->setacl($fname, $imapadm, "lrswipcda");
    if($$ret{Status} ne "ok") {
        y2internal("setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        $errtxt .= "setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
        #return undef;
    }
    if( $what eq "group" ) {       
        $ret = $imap->setacl($fname, "group:$fname", "lrswipcda");
        if($$ret{Status} ne "ok") {
            y2internal("setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
            $errtxt .= "setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
            #return undef;
        }
    }
    
    $ret = $imap->deleteacl($fname, "anyone");
    if($$ret{Status} ne "ok") {
        y2internal("deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        $errtxt .= "deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
        #return undef;
    }
    
    if( $data->{'imapquota'} ) {
        $ret = $imap->setquota($fname, ("STORAGE", $data->{'imapquota'} ) );
        if($$ret{Status} ne "ok") {
            y2internal("setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
            $errtxt .= "setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
            #return undef;
        }
    }
    return $errtxt;   
}

sub subscribe_mbox {
    my $imaphost   = shift;
    my $uid        = shift;
    my $imapadm    = shift;
    my $imapadmpw  = shift;
    
    my $errtxt     = "";
    my $proxy_imap = new Net::IMAP($imaphost, Debug => 0);
    unless ($proxy_imap) {
        y2internal("can't connect to $imaphost: $!\n");
        $errtxt .= "can't connect to $imaphost: $!";
        return undef;
    }
    my $ret = $proxy_imap->authenticate("PLAIN", ( $uid, $imapadm, $imapadmpw));
    if ( ! $ret ) {
        y2internal("Authentication failed. Mechanism \"PLAIN\" not available\n");
        $errtxt .= "Authentication failed. Mechanism \"PLAIN\" not available\n";
        return undef;
    } elsif ( $$ret{Status} ne "ok" ) {
        y2internal("authenticate failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        $errtxt .= "authenticate failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
        return undef;
    }
    $ret = $proxy_imap->subscribe( 'INBOX' );
    if ( $$ret{Status} ne "ok" ) {
        y2internal("subscribe failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        $errtxt .= "subscribe failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
        return undef;
    }
    $proxy_imap->logout();
    return $errtxt;
}

##--------------------------------------
@PluginMail::ISA    = qw(Exporter);
@PluginMail::EXPORT = qw(
                         &contains
			 &update_object_classes
			 &addRequiredMailData
			 &get_LDAP_Config
			 &cond_IMAP_OP
                        );
1
# EOF
