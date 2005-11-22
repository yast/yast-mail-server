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

# default object classes of LDAP users
my @user_object_class                  =
    ( "SuSEMailRecipient");

# default object classes of LDAP groups
my @group_object_class                 =
    ( "top", "posixgroup", "groupofnames");

# error message, returned when some plugin function fails
my $error       = "";

my $pluginName = "UsersPluginMail"; 
 
##--------------------------------------

# All functions have 2 "any" parameters: this will probably mean
# 1st: configuration map (hash) - e.g. saying if we work with user or group
# 2nd: data map (hash) of user (group) to work with

# in 'config' map there is a info of this type:
# "what"		=> "user" / "group"
# "modified"		=> "added"/"edited"/"deleted"
# "enabled"		=> 1/ key not present
# "disabled"		=> 1/ key not present

# 'data' map contains the atrtributes of the user. It could also contain
# some keys, which Users module uses internaly (like 'groupname' for name of
# user's default group). Just ignore these values
    
##------------------------------------


# return names of provided functions
BEGIN { $TYPEINFO{Interface} = ["function", ["list", "string"], "any", "any"];}
sub Interface {

    my $self		= shift;
    my @interface 	= (
	    "GUIClient",
	    "Check",
	    "Name",
	    "Summary",
	    "Restriction",
	    "WriteBefore",
	    "Write",
	    "AddBefore",
	    "Add",
	    "EditBefore",
	    "Edit",
	    "Interface",
            "PluginPresent",
	    "Disable",
	    "InternalAttributes",
	    "Error"
    );
    return \@interface;
}

# return error message, generated by plugin
BEGIN { $TYPEINFO{Error} = ["function", "string", "any", "any"];}
sub Error {
    
    my $self = shift;
    my $ret  = $error;
    $error   = "";
    return     $ret;
}

# this will be called at the beggining of Users::Edit
BEGIN { $TYPEINFO{InternalAttributes} = ["function", ["map", "string", "any"], "any", "any"]; }
sub InternalAttributes {
    return [ "localdeliverytype", "mainmaildomain", "imapquota", "imapquotaused" ];
}

# return plugin name, used for GUI (translated)
BEGIN { $TYPEINFO{Name} = ["function", "string", "any", "any"];}
sub Name {

    my $self		= shift;
    # plugin name
    return __("User Mail Attributes");
}

# return plugin summary
BEGIN { $TYPEINFO{Summary} = ["function", "string", "any", "any"];}
sub Summary {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    if( $config->{'what'} eq 'user' ) {
       return __("Edit user mail parameters");
    }
    if( $config->{'what'} eq 'group' ) {
      return __("Edit group mail parameters");
    }
    y2milestone( "MailPlugin: invalid use of UserMailPlugin");
    return undef;
}


# return name of YCP client defining YCP GUI
BEGIN { $TYPEINFO{GUIClient} = ["function", "string", "any", "any"];}
sub GUIClient {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    if( $config->{'what'} eq 'user' ) {
       return "users_plugin_mail";
    }
    if( $config->{'what'} eq 'group' ) {
       return "users_plugin_mail_groups";
    }
    y2milestone( "MailPlugin: invalid use of UserMailPlugin");
    return undef;
}

##------------------------------------
# Type of users and groups this plugin is restricted to.
# If this function doesn't exist, plugin is applied for all user (group) types.
BEGIN { $TYPEINFO{Restriction} = ["function", ["map", "string", "any"], "any", "any"];}
sub Restriction {

    my $self	= shift;
    # this plugin applies only for LDAP users and groups
    return { 
	     "ldap"	=> 1,
	     "user"     => 1,
	     "group"    => 1
	   };
}

# checks the current data map of user/group (2nd parameter) and returns
# true if given user (group) has our plugin
BEGIN { $TYPEINFO{PluginPresent} = ["function", "boolean", "any", "any"];}
sub PluginPresent {
    my $self	  = shift;
    my $config    = shift;
    my $data      = shift;

    if ( grep /^suseMailRecipient$/i, @{$data->{'objectclass'}} ) {
        y2milestone( "MailPlugin: Plugin Present");
        return 1;
    } else {
        y2milestone( "MailPlugin: Plugin not Present");
        return 0;
    }
}

##------------------------------------
# check if all required atributes of LDAP entry are present
# parameter is (whole) map of entry (user/group)
# return error message
BEGIN { $TYPEINFO{Check} = ["function", "string", "any", "any"]; }
sub Check {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;
    
    # attribute conversion
    my @required_attrs		= ();
    my @object_classes		= ();
    if (defined $data->{"objectclass"} && ref ($data->{"objectclass"}) eq "ARRAY") {
	@object_classes		= @{$data->{"objectclass"}};
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
	my $attr	= lc ($req);
	my $val		= $data->{$attr};
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
BEGIN { $TYPEINFO{Disable} = ["function", ["map", "string", "any"], "any", "any"]; }
sub Disable {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    y2internal ("Disable Mail called");
    return $data;
}


# this will be called at the beggining of Users::Add
# Could be called multiple times for one user/group!
BEGIN { $TYPEINFO{AddBefore} = ["function", ["map", "string", "any"], "any", "any"]; }
sub AddBefore {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    $data	= update_object_classes ($config, $data);

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
    }

    # looking for the main mail domain and returns
    return getMainDomain($data);
}

# This will be called just after Users::Add - the data map probably contains
# the values which we could use to create new ones
# Could be called multiple times for one user/group!
BEGIN { $TYPEINFO{Add} = ["function", ["map", "string", "any"], "any", "any"];}
sub Add {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    y2internal ("Add Mail called");
    y2debug(Dumper($data));
    return undef if !defined $data;
   
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

    return addRequiredMailData($config,$data);
}

# this will be called at the beginning of Users::Edit
BEGIN { $TYPEINFO{EditBefore} = ["function", ["map", "string", "any"], "any", "any"]; }
sub EditBefore {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    # data of original user/group are saved as a submap of $config
    # data with key "org_data"

    y2internal ("EditBefore Mail called");
    y2debug( Dumper($data) );

    # Only change objectclasses if they are already present (sometimes EditBefore 
    # is called with an empty $data hash)
    if ( $data->{'objectclass'} ) {
        $data	= update_object_classes ($config, $data);

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

    # looking for the main mail domain and returns
    return getMainDomain($data);

}

# this will be called just after Users::Edit
BEGIN { $TYPEINFO{Edit} = ["function", ["map", "string", "any"], "any", "any"]; }
sub Edit {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    y2internal ("Edit Mail called");
    y2debug(Dumper($data));

    if ( ! $data->{'imapquota'} ) {
        my $tmp_data = cond_IMAP_OP($config, $data, "getquota");
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

	return addRequiredMailData($config,$data);

    }

    return $data;
}

# what should be done before user is finally written to LDAP
BEGIN { $TYPEINFO{WriteBefore} = ["function", "boolean", "any", "any"];}
sub WriteBefore {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    y2internal ("WriteBefore Mail called");
    y2debug( Dumper($data) );

    if( $config->{'what'} eq 'user' ) {
       return if $data->{'uid'} eq "" || ! defined $data->{'uid'};
    }
    if( $config->{'what'} eq 'group' ) {
       return if $data->{'cn'} eq ""  || ! defined $data->{'cn'};
    }

    # looking for the local delivery type
    my $imapadmpw  = Ldap->bind_pass();
    my $MailLocalDelivery = YaPI::MailServer->ReadMailLocalDelivery($imapadmpw);
    $data->{'localdeliverytype'} = $MailLocalDelivery->{'Type'};

    # looking for the main mail domain
    getMainDomain($data);

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
    if ( ($data->{'what'} =~ /delete_/ ) && $self->PluginPresent($config, $data) ){
        cond_IMAP_OP($config, $data, "delete") if $action eq "deleted";
        # ignore errors here otherwise it might be possible, that a user can't
        # be deleted at all
        $error = "";
        return 1;
    }
    # Has the plugin been removed?
    if ( ($data->{'what'} =~ /^edit_/ ) && 
            (grep /^UsersPluginMail$/, @{$data->{'plugins_to_remove'}}) ){
        cond_IMAP_OP($config, $data, "delete");
        # ignore errors here otherwise it might be possible, that the plugin can't
        # be deleted for the user at all
        $error = "";
        return 1;
    }

    # Now the plugin stands or will be added
    # for the groups we hate to make some others
    if( $config->{'what'} eq 'group' ) {
      if(defined $data->{'susedeliverytomember'} && $data->{'susedeliverytomember'} eq 'yes') {
	$data->{'memberuid'} = [];
        foreach my $member (keys %{$data->{'member'}}){
          $member =~ /uid=(.*?),/; 
          push @{$data->{'memberuid'}},$1;
        }
      }
    }
    #DEBUG
    #y2internal(Dumper($data));
    if ( ($data->{'what'} =~ /^edit_/ ) && $self->PluginPresent($config, $data) ) {
        # create Folder if plugin has been added
        if ( ! grep /^suseMailRecipient$/i, @{$data->{'org_user'}->{'objectclass'}} ) {
            y2milestone("creating INBOX");
            cond_IMAP_OP($config, $data, "add") if $action eq "edited";
            return;
        } else {
            y2milestone("updating INBOX");
            cond_IMAP_OP($config, $data, "update") if $action eq "edited";
            return;
        }
    }
    
    return 1;
}

# what should be done after user is finally written to LDAP
BEGIN { $TYPEINFO{Write} = ["function", "boolean", "any", "any"];}
sub Write {

    my $self   = shift;
    my $config = shift;
    my $data   = shift;

    # this means what was done with a user: added/edited/deleted
    my $action = $config->{"modified"} || "";
    y2internal ("Write Mail called");
    y2debug( Dumper($data) );
    if ( ($data->{'what'} =~ /^add_/ ) && $self->PluginPresent($config, $data) ) {
        # create Folder if plugin has been added
        cond_IMAP_OP($config, $data, "add") if $action eq "added";
	return;
    }

    return 1;
}

#---------------------Helper Soubroutines---------------------------------------------
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

    my $config	= $_[0];
    my $data	= $_[1];

    # define the object class for new user/groupa
    my @orig_object_class	= ();
    if (defined $data->{"objectclass"} && ref $data->{"objectclass"} eq "ARRAY")
    {
	@orig_object_class	= @{$data->{"objectclass"}};
    }
    my @ocs			= @user_object_class;
    if (($config->{"what"} || "") eq "group") {
	@ocs			= @group_object_class;
    }
    foreach my $oc (@ocs) {
	if (!contains (\@orig_object_class, $oc, 1)) {
	    push @orig_object_class, $oc;
	}
    }

    $data->{"objectclass"}	= \@orig_object_class;

    return $data;
}

sub addRequiredMailData {
    my $config = shift;
    my $data   = shift;

    if( ! contains( $data->{objectclass}, "susemailrecipient", 1) ) {
	push @{$data->{'objectclass'}}, "susemailrecipient";
    }

    if( $config->{'what'} eq 'group' ) {
       # We do not need do anithing else for groups.
       return $data;
    }

    if( ! defined $data->{'uid'} || $data->{'uid'} eq "" ) {
       # If no uid has been defined yet we have to return.
       return $data;
    }
    my $mailaddress = $data->{'uid'}."\@".$data->{mainmaildomain};
    if( defined $data->{susemailacceptaddress} ) {
	if( ref($data->{susemailacceptaddress}) eq "ARRAY" &&
	    ! contains( $data->{susemailacceptaddress}, $mailaddress, 1) ) {
	    push @{$data->{'susemailacceptaddress'}}, $mailaddress;
	} elsif ( ref($data->{susemailacceptaddress}) ne "ARRAY" &&
		  $data->{susemailacceptaddress} ne $mailaddress ) {
	    my $tmp = $data->{'susemailacceptaddress'};
	    $data->{'susemailacceptaddress'} = [];
	    push @{$data->{'susemailacceptaddress'}}, $tmp;
	    push @{$data->{'susemailacceptaddress'}}, $mailaddress;
	}
    } else {
	$data->{susemailacceptaddress} = $mailaddress;
    }

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

sub getMainDomain {
    my $data    = shift;

    my $ldapMap = Ldap->Export();
    my $domain;
    # read dns configuration data
    my $ret = SCR->Read(".ldap.search", {
        "base_dn"      => $ldapMap->{'base_config_dn'},
        "filter"       => '(objectclass=suseDnsConfiguration)',
        "scope"        => 2,
        "not_found_ok" => 1,
        "attrs"        => [ 'suseDefaultBase' ]
        });
    if (!$ret) {
        my $ldapERR = SCR->Read(".ldap.error");
	$error = "LDAP Search failed: ".$ldapERR->{'code'}." : ".$ldapERR->{'msg'};
        return undef;
    }
    if(@$ret > 0) {
        $ldapMap->{'dns_config_dn'} = $ret->[0]->{'susedefaultbase'}->[0];
    } else {
        my $ldapERR = SCR->Read(".ldap.error");
	$error = "DNS Setup Error: ".$ldapERR->{'code'}." : ".$ldapERR->{'msg'};
        return undef;
    }
    # now we read the main domain
    $ret = SCR->Read(".ldap.search", {
	"base_dn"      => $ldapMap->{'dns_config_dn'},
	"filter"       => '(&(relativeDomainName=@)(SuSEMailDomainType=main))',
	"scope"        => 2,
	"not_found_ok" => 1,
	"attrs"        => [ 'zoneName']
	});
    
    if (! defined $ret) {
        my $ldapERR = SCR->Read(".ldap.error");
	$error = "LDAP search failed: ".$ldapERR->{'code'}." : ".$ldapERR->{'msg'};
        return undef;
    }
    if(@$ret == 0) {
	$error = "No main domain defined";
        return undef;
    } elsif ( @$ret > 1 ) {
	$error = "More then one main domain";
        return undef;
    } else {
        $domain = $ret->[0]->{'zonename'}->[0];
    }
    $data->{'mainmaildomain'} = $domain;

    return $data;
}

sub cond_IMAP_OP {
    my $config = shift;
    my $data   = shift;
    my $op     = shift || "add";

    my $fname  = "";
    if(!defined $data->{'localdeliverytype'} || $data->{'localdeliverytype'} ne 'cyrus') {
	return $data
    }
    my $imapadm    = "cyrus";
    my $imaphost   = "localhost";
    my $imapquota  = "-1";

    my $ldapret = get_LDAP_Config();

    if(@$ldapret > 0) {
	$imapadm    = $ldapret->[0]->{'suseimapadmin'}->[0];
	$imaphost   = $ldapret->[0]->{'suseimapserver'}->[0];
	#$imapquota  = $ldapret->[0]->{'suseimapdefaultquota'}->[0];
    }
    
    if ( $data->{'imapquota'} ) {
        $imapquota = $data->{'imapquota'};
    }

    # we need to ensure, that imapadmpw == rootdnpw!
    my $imapadmpw  = Ldap->bind_pass();

    # make IMAP connection
    my $imap = new Net::IMAP($imaphost, Debug => 0);
    unless ($imap) {
        y2internal("can't connect to $imaphost: $!\n");
	$error = "can't connect to $imaphost: $!";
        return undef;
    }

    # review the capability of the IMAP server
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

    if( $config->{'what'} eq 'user' ) {
        # the namespace of the IMAP serve is only for user mail boxes important
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
        
        # y2internal("hsep = <$hsep>\n");
        
        $fname = "user".$hsep.$data->{uid};
        
        #y2internal(Dumper(\@users_ns));
        #y2internal(Dumper($namespace));
    } else {
        $fname = $data->{cn};
    }

    if( $op eq "add" ) {
	my $errtxt = "";
	$ret = $imap->create($fname);
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

	$ret = $imap->deleteacl($fname, "anyone");
	if($$ret{Status} ne "ok") {
	    y2internal("deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
	    $errtxt .= "deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
	    #return undef;
	}
	
        if( $config->{'what'} eq 'group' ) {
            # Make acl for the group member
            $ret = $imap->setacl($fname, 'group:'.$data->{cn}, "lrswipcd");
            if($$ret{Status} ne "ok") {
                y2internal("setacl for group failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                $errtxt .= "setacl for group failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                #return undef;
            }
        }
	if( $imapquota > -1 ) {
	    $ret = $imap->setquota($fname, ("STORAGE", $imapquota ) );
	    if($$ret{Status} ne "ok") {
		y2internal("setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
		$errtxt .= "setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
		#return undef;
	    }
	}
	if( $errtxt ne "" ) {
	    $error = $errtxt;
	    return undef;
	} elsif ($config->{'what'} eq 'user') {
            # The mail box must be subscribed for the user
            my $proxy_imap = new Net::IMAP($imaphost, Debug => 0);
            unless ($proxy_imap) {
                y2internal("can't connect to $imaphost: $!\n");
                $error = "can't connect to $imaphost: $!";
                return undef;
            }
            $ret = $proxy_imap->authenticate("PLAIN", ( $data->{uid}, $imapadm, $imapadmpw));
            if ( ! $ret ) {
                y2internal("Authentication failed. Mechanism \"PLAIN\" not available\n");
                $error = "Authentication failed. Mechanism \"PLAIN\" not available\n";
                return undef;
            } elsif ( $$ret{Status} ne "ok" ) {
		y2internal("authenticate failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                $error = "authenticate failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                return undef;
            }
            $ret = $proxy_imap->subscribe( 'INBOX' );
            if ( $$ret{Status} ne "ok" ) {
		y2internal("subscribe failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                $error = "subscribe failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                return undef;
            }
            $proxy_imap->logout();
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
	    	# Recreate mail box
                my $errtxt = "";
                $ret = $imap->create($fname);
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
                
                $ret = $imap->deleteacl($fname, "anyone");
                if($$ret{Status} ne "ok") {
                    y2internal("deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                    $errtxt .= "deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                    #return undef;
                }
                
                if( $config->{'what'} eq 'group' ) {
                    # Make acl for the group member
                    $ret = $imap->setacl($fname, 'group:'.$data->{cn}, "lrswipcd");
                    if($$ret{Status} ne "ok") {
                        y2internal("setacl for group failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                        $errtxt .= "setacl for group failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                        #return undef;
                    }
                }
                if( $imapquota ) {
                    $ret = $imap->setquota($fname, ("STORAGE", $imapquota ) );
                    if($$ret{Status} ne "ok") {
                	y2internal("setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                	$errtxt .= "setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                	#return undef;
                    }
                }
                if( $errtxt ne "" ) {
                    $error = $errtxt;
                    return undef;
                } elsif ($config->{'what'} eq 'user') {
                    # The mail box must be subscribed for the user
                    my $proxy_imap = new Net::IMAP($imaphost, Debug => 0);
                    unless ($proxy_imap) {
                        y2internal("can't connect to $imaphost: $!\n");
                        $error = "can't connect to $imaphost: $!";
                        return undef;
                    }
                    $ret = $proxy_imap->authenticate("PLAIN", ( $data->{uid}, $imapadm, $imapadmpw));
                    if ( ! $ret ) {
                        y2internal("Authentication failed. Mechanism \"PLAIN\" not available\n");
                        $error = "Authentication failed. Mechanism \"PLAIN\" not available\n";
                        return undef;
                    } elsif ( $$ret{Status} ne "ok" ) {
                	y2internal("authenticate failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                        $error = "authenticate failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                        return undef;
                    }
                    $ret = $proxy_imap->subscribe( 'INBOX' );
                    if ( $$ret{Status} ne "ok" ) {
                	y2internal("subscribe failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                        $error = "subscribe failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                        return undef;
                    }
                    $proxy_imap->logout();
                }
                    } else {
                        if( defined $data->{'imapquota'} && $data->{'imapquota'} > 0 ) {
                            $ret = $imap->setquota($fname, ("STORAGE", $data->{'imapquota'} ) );
                            if($$ret{Status} ne "ok") {
                                y2internal("setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                                $error = "setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}";
                                return undef;
                            }
                	} else {
                	    $ret = $imap->setquota($fname, () );
                	    if($$ret{Status} ne "ok") {
                		y2internal("setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
                		$error = "setquota failed: Serverresponse:$$ret{Status} => $$ret{Text}\n";
                		return undef;
                	    }
                        }
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

1
# EOF
