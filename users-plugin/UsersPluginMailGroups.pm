#! /usr/bin/perl -w
#
# Example of plugin module
# This is the API part of UsersPluginMail plugin - configuration of
# all user/group LDAP attributes
#

package UsersPluginMail;

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
##--------------------- global variables

# default object classes of LDAP mail group
my @required_object_class                =
    ( "SuSEMailRecipient");

# error message, returned when some plugin function fails
my $error       = "";

my $pluginName = "UsersPluginMailGroup"; 

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
    
    if( ! contains( $data->{objectclass}, "susemailrecipient", 1) ) {
        push @{$data->{'objectclass'}}, "susemailrecipient";
    }
    
    return undef if !defined $data;
    return $data if !defined $data->{'cn'} || $data->{'cn'} eq "";
    
    $data->{susemailcommand} = '"|/usr/bin/formail -I \"From \" |/usr/lib/cyrus/bin/deliver -r '.$data->{'cn'}.' -a cyrus -m '.$data->{'cn'}.'"';

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
    my $errtxt = "";
    my $imapadm;
    my $imaphost;
    my $imapquota;
    
    my $cn = $data->{'cn'};
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
    
    if ( $data->{'imapquota'} ) {
        $imapquota = $data->{'imapquota'};
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
   
    if( $op eq "add" ) {
        $ret = $imap->create($cn);
        if($$ret{Status} ne "ok" && $$ret{Text} !~ /Mailbox already exists/) {
            y2internal("create failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
            $errtxt .= "create failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
            #return undef;
        }
        
        $ret = $imap->setacl($cn, $imapadm, "lrswipcda");
        if($$ret{Status} ne "ok") {
            y2internal("setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
            $errtxt .= "setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
            #return undef;
        }
        
        $ret = $imap->setacl($cn, "group:$cn", "lrswipcda");
        if($$ret{Status} ne "ok") {
            y2internal("setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
            $errtxt .= "setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
            #return undef;
        }

        $ret = $imap->deleteacl($cn, "anyone");
        if($$ret{Status} ne "ok") {
            y2internal("deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
            $errtxt .= "deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
            #return undef;
        }
        
        if( $imapquota ) {
            $ret = $imap->setquota($cn, ("STORAGE", $imapquota ) );
            if($$ret{Status} ne "ok") {
                y2internal("setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                $errtxt .= "setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                #return undef;
            }
        }
	if( $errtxt ne "" ) {
            $error = "add failed: ".$errtxt;
            return undef;
	}
    } elsif( $op eq "delete" ) {
       $ret = $imap->delete($cn);
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
        
        $ret = $imap->list("", $cn);
        
        if ($$ret{Status} ne "ok")  {
            y2internal("list failed: Serverresponse:$$ret{Status} => $$ret{Text}");
            $error = "list failed: Serverresponse:$$ret{Status} => $$ret{Text}";
            return undef;
        } else {
            if( scalar(@__folder) == 0  ) {
                # Mailbox doesn't exist -> recreate it
                y2milestone("recreating Mailbox $cn");
                my $errtxt = "";
                $ret = $imap->create($cn);
                if($$ret{Status} ne "ok") {
                    y2internal("create failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                    $errtxt .= "create failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                    #return undef;
                }
                
                $ret = $imap->setacl($cn, $imapadm, "lrswipcda");
                if($$ret{Status} ne "ok") {
                    y2internal("setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                    $errtxt .= "setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                    #return undef;
                }
                $ret = $imap->setacl($cn, "group:$cn", "lrswipcda");
                if($$ret{Status} ne "ok") {
                    y2internal("setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                    $errtxt .= "setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                    #return undef;
                }
                
                $ret = $imap->deleteacl($cn, "anyone");
                if($$ret{Status} ne "ok") {
                    y2internal("deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                    $errtxt .= "deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                    #return undef;
                }
                
                if( $imapquota && $data->{'imapquota'} > 0 ) {
                    $ret = $imap->setquota($cn, ("STORAGE", $imapquota ) );
                    if($$ret{Status} ne "ok") {
                        y2internal("setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                        $errtxt .= "setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                        #return undef;
                    }
                } else {
                    $ret = $imap->setquota($cn, () );
                    if($$ret{Status} ne "ok") {
                        y2internal("setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                        $errtxt .= "setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                        #return undef;
                    }
                }
            }
	    if( $errtxt ne "" ) {
                $error = "update failed: ".$errtxt;
                return undef;
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
    
        $ret = $imap->getquotaroot($cn);
        if($$ret{Status} ne "ok") {
            y2internal("getquotaroot failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        }
    }
    
    $imap->logout();
    return $data;
}
##--------------------------------------

# All functions have 2 "any" parameters: this will probably mean
# 1st: configuration map (hash) - e.g. saying if we work with user or group
# 2nd: data map (hash) of user (group) to work with

# in 'config' map there is a info of this type:
# "what"        => "user" / "group"
# "modified"        => "added"/"edited"/"deleted"
# "enabled"        => 1/ key not present
# "disabled"        => 1/ key not present

# 'data' map contains the atrtributes of the user. It could also contain
# some keys, which Users module uses internaly (like 'groupname' for name of
# user's default group). Just ignore these values
    
##------------------------------------


# return names of provided functions
BEGIN { $TYPEINFO{Interface} = ["function", ["list", "string"], "any", "any"];}
sub Interface {

    my $self        = shift;
    my @interface     = (
        "Interface",
        "Error",
        "InternalAttributes",
        "Name",
        "Summary",
        "GUIClient",
        "Restriction",
            "PluginPresent",
        "Check",
        "Disable",
        "AddBefore",
        "Add",
        "WriteBefore",
        "Write",
        "EditBefore",
        "Edit",
    );
    return \@interface;
}

# return error message, generated by plugin
BEGIN { $TYPEINFO{Error} = ["function", "string", "any", "any"];}
sub Error {
    
    my $self            = shift;
    my $ret = $error;
    $error = "";
    return $ret;
}

# this will be called at the beggining of Users::Edit
BEGIN { $TYPEINFO{InternalAttributes} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub InternalAttributes {
#    return [ "localdeliverytype" , "imapquota", "imapquotaused"];
    return [ "localdeliverytype"];
}

# return plugin name, used for GUI (translated)
BEGIN { $TYPEINFO{Name} = ["function", "string", "any", "any"];}
sub Name {

    my $self        = shift;
    # plugin name
    return __("Group Mail Attributes");
}

# return plugin summary
BEGIN { $TYPEINFO{Summary} = ["function", "string", "any", "any"];}
sub Summary {

    my $self    = shift;
    my $what    = "group";
    # summary
    my $ret     = __("Edit group mail parameters");

    return $ret;
}


# return name of YCP client defining YCP GUI
BEGIN { $TYPEINFO{GUIClient} = ["function", "string", "any", "any"];}
sub GUIClient {

    my $self    = shift;
    return "users_plugin_mail_group";
}

##------------------------------------
# Type of users and groups this plugin is restricted to.
# If this function doesn't exist, plugin is applied for all user (group) types.
BEGIN { $TYPEINFO{Restriction} = ["function",
    ["map", "string", "any"], "any", "any"];}
sub Restriction {

    my $self    = shift;
    # this plugin applies only for LDAP users and groups
    return { "ldap"    => 1,
         "group"    => 1};
}

# checks the current data map of user/group (2nd parameter) and returns
# true if given user (group) has our plugin
BEGIN { $TYPEINFO{PluginPresent} = ["function", "boolean", "any", "any"];}
sub PluginPresent {
    my $self    = shift;
    my $config  = shift;
    my $data    = shift;
    if ( grep /^suseMailRecipient$/i, @{$data->{'objectclass'}} ) {
        y2milestone( "MailPluginGroup: Plugin Present");
        return 1;
    } else {
        y2milestone( "MailPluginGroup: Plugin not Present");
        return 0;
    }
}

##------------------------------------
# check if all required atributes of LDAP entry are present
# parameter is (whole) map of entry (user/group)
# return error message
BEGIN { $TYPEINFO{Check} = ["function",
    "string",
    "any",
    "any"];
}
sub Check {

    my $self    = shift;
    my $config    = $_[0];
    my $data    = $_[1];
    
    # attribute conversion
    my @required_attrs        = ();
    my @object_classes        = ();
    if (defined $data->{"objectclass"} && ref ($data->{"objectclass"}) eq "ARRAY") {
    @object_classes        = @{$data->{"objectclass"}};
    }

    # get the attributes required for entry's object classes
    foreach my $class (@object_classes) {
    my $object_class = SCR->Read (".ldap.schema.oc", {"name"=> $class});
    if (!defined $object_class || ref ($object_class) ne "HASH" ||
        ! %{$object_class}) { next; }
    my $req = $object_class->{"must"};
    if (defined $req && ref ($req) eq "ARRAY") {
        foreach my $r (@{$req}) {
        push @required_attrs, $r;
        }
    }
    }

    # check the presence of required attributes
    foreach my $req (@required_attrs) {
    my $attr    = lc ($req);
    my $val        = $data->{$attr};
    if (!defined $val || $val eq "" || 
        (ref ($val) eq "ARRAY" && 
        ((@{$val} == 0) || (@{$val} == 1 && $val->[0] eq "")))) {
        # error popup (user forgot to fill in some attributes)
        return sprintf (__("The attribute '%s' is required for this object according
to its LDAP configuration, but it is currently empty."), $attr);
    }
    }
    return "";
}

# this will be called at the beggining of Users::Edit
BEGIN { $TYPEINFO{Disable} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub Disable {

    my $self    = shift;
    my $config    = $_[0];
    my $data    = $_[1];

    y2internal ("Disable Mail called");
    return $data;
}


# this will be called at the beggining of Users::Add
# Could be called multiple times for one user/group!
BEGIN { $TYPEINFO{AddBefore} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub AddBefore {

    my $self    = shift;
    my $config    = $_[0];
    my $data    = $_[1]; # only new data that will be copied to current user map

    $data    = update_object_classes ($config, $data);

    y2internal ("AddBefore Mail called");
    y2debug(Dumper($data));
    my $ldapret = get_LDAP_Config();

    if(@$ldapret <= 0) {
    $error = __("Run the mail server module first.");
    y2internal("You have to run the mail-server module, first.");
    return undef;
    }
    #print "AddBefore";
    #print Dumper($data);
    y2internal ("AddBefore Mail leaving");
    y2debug(Dumper($data));

    # looking for the local delivery type
    my $imapadmpw  = Ldap->bind_pass();
    my $MailLocalDelivery = YaPI::MailServer->ReadMailLocalDelivery($imapadmpw);
    $data->{'localdeliverytype'} = $MailLocalDelivery->{'Type'};
    if($data->{'localdeliverytype'} eq 'cyrus' ) {
        #setting default quota
        $data->{'imapquota'} =  $ldapret->[0]->{'suseimapdefaultquota'}->[0];
    } else {
    $error = __("Mailserver attributes for group are only avaiable if cyrus-IMAP is the local delivery system.");
    y2internal("Mailserver attributes for group are only avaiable if cyrus-IMAP is the local delivery system.");
    return undef;
    }

    return $data;
}

# This will be called just after Users::Add - the data map probably contains
# the values which we could use to create new ones
# Could be called multiple times for one user/group!
BEGIN { $TYPEINFO{Add} = ["function", ["map", "string", "any"], "any", "any"];}
sub Add {

    my $self    = shift;
    my $config    = $_[0];
    my $data    = $_[1]; # the whole map of current user/group after Users::Edit

    y2internal ("Add Mail called");
    y2debug(Dumper($data));
    return undef if !defined $data;
    return $data if !defined $data->{'cn'} || $data->{'cn'} eq "";
   
    if( grep /^UsersPluginMail$/, @{$data->{'plugins_to_remove'}} ) {
        my @updated_oc;
        foreach my $oc ( @{$data->{'objectclass'}} ) {
            if ( lc($oc) ne "susemailrecipient" ) {
                push @updated_oc, $oc;
            }
        }
        delete( $data->{'imapquota'});
        delete( $data->{'imapquotaused'});

        $data->{'objectclass'} = \@updated_oc;
        y2debug ("Removed Mail plugin");
        y2debug ( Data::Dumper->Dump( [ $data ] ) );
        return $data;
    }

    return addRequiredMailData($data);
}

# this will be called at the beginning of Users::Edit
BEGIN { $TYPEINFO{EditBefore} = ["function", ["map", "string", "any"], "any", "any"]; }
sub EditBefore {

    my $self    = shift;
    my $config    = $_[0];
    my $data    = $_[1]; # only new data that will be copied to current user map
    # data of original user/group are saved as a submap of $config
    # data with key "org_data"
    
    y2internal ("EditBefore Mail called");
    y2debug( Dumper($data) );
    
    # Only change objectclasses if they are already present (sometimes EditBefore 
    # is called with an empty $data hash)
    if ( $data->{'objectclass'} ) {
        $data    = update_object_classes ($config, $data);
        
        my $ldapret = get_LDAP_Config();
        
        if(@$ldapret <= 0) {
            $error = __("Run the mail server module first.");
            return undef;
        }
    }
    
    # looking for the local delivery type
    my $imapadmpw  = Ldap->bind_pass();
    my $MailLocalDelivery = YaPI::MailServer->ReadMailLocalDelivery($imapadmpw);
    $data->{'localdeliverytype'} = $MailLocalDelivery->{'Type'};
    
    return $data;
}

# this will be called just after Users::Edit
BEGIN { $TYPEINFO{Edit} = ["function", ["map", "string", "any"], "any", "any"]; }
sub Edit {

my $self    = shift;
my $config    = $_[0];
my $data    = $_[1]; # the whole map of current user/group after Users::Edit

y2internal ("Edit Mail called");
y2debug(Dumper($data));

if ( ! $data->{'imapquota'} ) {
my $tmp_data = cond_IMAP_OP($data, "getquota");
if( $tmp_data ) {
    $data = $tmp_data;
}
}
# Has the plugin been removed?
if( grep /^UsersPluginMail$/, @{$data->{'plugins_to_remove'}} ) {
my @updated_oc;
foreach my $oc ( @{$data->{'objectclass'}} ) {
    if ( lc($oc) ne "susemailrecipient" ) {
    push @updated_oc, $oc;
    }
}
delete( $data->{'imapquota'});
delete( $data->{'imapquotaused'});

$data->{'objectclass'} = \@updated_oc;

y2milestone ("Removed Mail plugin");
y2debug ( Data::Dumper->Dump( [ $data ] ) );
} else {
# get default domain name from LDAP
my $domain = getMainDomain();

if ( !defined $domain || $domain eq "" ){
    if( $error ne "" ){
    y2internal($error);
    y2internal("Disabling: $pluginName");
    $error = "";
    }

    # Remove "UserPluginMail" from plugin list
    my @updated_plugin;
    foreach my $plugin ( @{$data->{'plugins'}} ) {
    if ( lc($plugin) ne lc($pluginName) ) {
        push @updated_plugin, $plugin;
    }
    }
    $data->{'plugins'} = \@updated_plugin;

    # Remove "suseMailReceipient" from objectclasses
    my @updated_oc;
    foreach my $oc ( @{$data->{'objectclass'}} ) {
    if ( lc($oc) ne "susemailrecipient" ) {
        push @updated_oc, $oc;
    }
    }
    delete( $data->{'imapquota'});
    delete( $data->{'imapquotaused'});
    $data->{'objectclass'} = \@updated_oc;

    return $data;
}
    
return $data if !defined $data->{'uid'};

return addRequiredMailData($data);
}

return $data;
}


# what should be done before user is finally written to LDAP
BEGIN { $TYPEINFO{WriteBefore} = ["function", "boolean", "any", "any"];}
sub WriteBefore {

    my $self    = shift;
    my $config    = $_[0];
    my $data    = $_[1];

    y2internal ("WriteBefore Mail called");
    y2debug( Dumper($data) );

    return if $data->{'uid'} eq "" || ! defined $data->{'uid'};

    # looking for the local delivery type
    my $imapadmpw  = Ldap->bind_pass();
    my $MailLocalDelivery = YaPI::MailServer->ReadMailLocalDelivery($imapadmpw);
    $data->{'localdeliverytype'} = $MailLocalDelivery->{'Type'};

    # this means what was done with a user/group: added/edited/deleted
    my $action = $config->{"modified"} || "";

    #y2internal(Dumper($config));
    #y2internal("ACTION=$action\n");
    
    my $ldapret = get_LDAP_Config();

    if(@$ldapret <= 0) {
    $error = __("Run the mail server module first.");
    y2internal("You have to run the mail-server module, first.");
    return undef;
    }

    # is the user being deleted?
    if ( ($data->{'what'} eq "delete_user" ) && $self->PluginPresent($config, $data) ){
        cond_IMAP_OP($data, "delete") if $action eq "deleted";
        # ignore errors here otherwise it might be possible, that a user can't
        # be deleted at all
        $error = "";
        return 1;
    }
    # Has the plugin been removed?
    if ( ($data->{'what'} eq "edit_user" ) && 
            (grep /^UsersPluginMail$/, @{$data->{'plugins_to_remove'}}) ){
        cond_IMAP_OP($data, "delete");
        # ignore errors here otherwise it might be possible, that the plugin can't
        # be deleted for the user at all
        $error = "";
        return 1;
    }

    if ( ($data->{'what'} eq "edit_user" ) && $self->PluginPresent($config, $data) ) {
        # create Folder if plugin has been added
        if ( ! grep /^suseMailRecipient$/i, @{$data->{'org_user'}->{'objectclass'}} ) {
            y2milestone("creating INBOX");
            cond_IMAP_OP($data, "add") if $action eq "edited";
            return;
        } else {
            y2milestone("updating INBOX");
            cond_IMAP_OP($data, "update") if $action eq "edited";
            return;
        }
    }
    
    return 1;
}

# what should be done after user is finally written to LDAP
BEGIN { $TYPEINFO{Write} = ["function", "boolean", "any", "any"];}
sub Write {

    my $self    = shift;
    my $config    = $_[0];
    my $data    = $_[1];

    # this means what was done with a user: added/edited/deleted
    my $action = $config->{"modified"} || "";
    y2internal ("Write Mail called");
    y2debug( Dumper($data) );
    if ( ($data->{'what'} eq "add_user" ) && $self->PluginPresent($config, $data) ) {
        # create Folder if plugin has been added
        cond_IMAP_OP($data, "add") if $action eq "added";
        return;
    }
    return 1;
}
1
# EOF
