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

our %TYPEINFO;


use Locale::gettext;
use POSIX ();
use Net::IMAP;
use Data::Dumper;
use Net::IMAP;

POSIX::setlocale(LC_MESSAGES, "");
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
	    "Disable",
#	    "InternalAttributes",
    );
    return \@interface;
}

# return plugin name, used for GUI (translated)
BEGIN { $TYPEINFO{Name} = ["function", "string", "any", "any"];}
sub Name {

    my $self		= shift;
    # plugin name
    return _("LDAP Attributes");
}

# return plugin summary
BEGIN { $TYPEINFO{Summary} = ["function", "string", "any", "any"];}
sub Summary {

    my $self	= shift;
    my $what	= "user";
    # summary
    my $ret 	= _("Edit user mail parameters");

    return $ret;
}

# return plugin internal attributes (which shouldn't be shown to user)
BEGIN { $TYPEINFO{InternalAttributes} = ["function",
    [ "list", "string" ], "any", "any"];
}
sub InternalAttributes {

    my $self	= shift;
    my @ret 	= ();

    if (defined $_[0]->{"what"} && $_[0]->{"what"} eq "group") {
	@ret 	= ();
    }
    return \@ret;
}


# return name of YCP client defining YCP GUI
BEGIN { $TYPEINFO{GUIClient} = ["function", "string", "any", "any"];}
sub GUIClient {

    my $self	= shift;
    return "users_plugin_mail";
}

##------------------------------------
# Type of users and groups this plugin is restricted to.
# If this function doesn't exist, plugin is applied for all user (group) types.
BEGIN { $TYPEINFO{Restriction} = ["function",
    ["map", "string", "any"], "any", "any"];}
sub Restriction {

    my $self	= shift;
    # this plugin applies only for LDAP users and groups
    return { "ldap"	=> 1,
	     "user"     => 1};
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

    my $self	= shift;
    my $config	= $_[0];
    my $data	= $_[1];
    
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
	    return sprintf (_("The attribute '%s' is required for this object according
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

    my $self	= shift;
    my $config	= $_[0];
    my $data	= $_[1];

    y2internal ("Disable Mail called");
    return $data;
}


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

# this will be called at the beggining of Users::Add
# Could be called multiple times for one user/group!
BEGIN { $TYPEINFO{AddBefore} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub AddBefore {

    my $self	= shift;
    my $config	= $_[0];
    my $data	= $_[1]; # only new data that will be copied to current user map

    $data	= update_object_classes ($config, $data);

    y2internal ("AddBefore Mail called");
    return $data;
}


# This will be called just after Users::Add - the data map probably contains
# the values which we could use to create new ones
# Could be called multiple times for one user/group!
BEGIN { $TYPEINFO{Add} = ["function", ["map", "string", "any"], "any", "any"];}
sub Add {

    my $self	= shift;
    my $config	= $_[0];
    my $data	= $_[1]; # the whole map of current user/group after Users::Edit

    return $data if $data->{'uid'} eq "" || ! defined $data->{'uid'};

    y2internal ("Add Mail called");

    cond_IMAP_OP($data->{'uid'}, "add");

    return addRequiredMailData($data);
}

# this will be called at the beggining of Users::Edit
BEGIN { $TYPEINFO{EditBefore} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub EditBefore {

    my $self	= shift;
    my $config	= $_[0];
    my $data	= $_[1]; # only new data that will be copied to current user map
    # data of original user/group are saved as a submap of $config
    # data with key "org_data"

    $data	= update_object_classes ($config, $data);

    y2internal ("EditBefore Mail called");
    return $data;
}

# this will be called just after Users::Edit
BEGIN { $TYPEINFO{Edit} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub Edit {

    my $self	= shift;
    my $config	= $_[0];
    my $data	= $_[1]; # the whole map of current user/group after Users::Edit

    my $addresses = $data->{"susemailacceptaddress"};
    y2internal(Dumper($addresses));
    my $naddr = undef;
    if( ref($addresses) ne "ARRAY" ) {
	$addresses =~ s/\s//g;
	$naddr = $addresses if $addresses eq "";
    } else {
	foreach my $a ( @$addresses ) {
	    $a =~ s/\s//g;
	    push @$naddr, $a if $a ne "";
	}
    }
    $data->{"susemailacceptaddress"} = $naddr;
    y2internal(Dumper($data));

    #cond_IMAP_OP($data->{'uid'}, "add");

    y2internal ("Edit Mail called");
    return $data;
}

sub cond_IMAP_OP {
    my $uid = shift;
    my $op  = shift || "add";

    # FIXME: How must Error handling be done here?
    # FIXME: we need to somehow get this data elsewhere
    my $imapadm    = "cyrus";
    my $imaphost   = "localhost";

    # FIXME: we need to ensure, that imapadmpw == rootdnpw!
    my $imapadmpw  = Ldap->bind_pass();

    #y2internal("imapadmpw = <$imapadmpw>\n");

    my $imap = new Net::IMAP($imaphost, Debug => 0);
    unless ($imap) {
        y2internal("can't connect to $imaphost: $!\n");
        return undef;
    }

    my $ret = $imap->login($imapadm, $imapadmpw);
    if($$ret{Status} ne "ok") {
        y2internal("login failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        return undef;
    }

    my $namespace;
    my $nscb = sub {
        my $self = shift;
        $namespace = shift;
    };

    $imap->set_untagged_callback('namespace', $nscb);

    $ret = $imap->namespace();
    if($$ret{Status} ne "ok") {
        y2internal("namespace failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
        return undef;
    }

    my @users_ns = $namespace->other_users();
    
    # UGLY: Access the Namespace-Structure directly, as the access method lowercase the values
    my $hsep = $namespace->{'Namespaces'}->{'other_users'}->{$users_ns[0]}; 

    # y2internal("hsep = <$hsep>\n");
   
    my $fname = "user".$hsep.$uid;

    #y2internal(Dumper(\@users_ns));
    #y2internal(Dumper($namespace));

    if( $op eq "add" ) {
	$ret = $imap->create($fname);
	if($$ret{Status} ne "ok") {
	    y2internal("create failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
	    #return undef;
	}
	
	$ret = $imap->deleteacl($fname, "anyone");
	if($$ret{Status} ne "ok") {
	    y2internal("deleteacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
	    #return undef;
	}
	
	$ret = $imap->setacl($fname, $imapadm, "lrswipcda");
	if($$ret{Status} ne "ok") {
	    y2internal("setacl failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
	    #return undef;
	}
    } elsif( $op eq "delete" ) {
	$ret = $imap->delete($fname);
	if($$ret{Status} ne "ok") {
	    y2internal("delete failed: Serverresponse:$$ret{Status} => $$ret{Text}\n");
	    #return undef;
	}
    }

    $imap->logout();
}

sub addRequiredMailData {
    my $data = shift;

    if( ! contains( $data->{objectclass}, "susemailrecipient", 1) ) {
	push @{$data->{'objectclass'}}, "susemailrecipient";
    }

    # FIXME: why are we called several times and sometimes uid is empty???
    return $data if $data->{'uid'} eq "" || ! defined $data->{'uid'};

    # FIXME: get default domain name from LDAP
    my $domain = "suse.de";
    my $mailaddress = $data->{'uid'}."\@".$domain;
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

# what should be done before user is finally written to LDAP
BEGIN { $TYPEINFO{WriteBefore} = ["function", "boolean", "any", "any"];}
sub WriteBefore {

    my $self	= shift;
    my $config	= $_[0];
    my $data	= $_[1];

    return if $data->{'uid'} eq "" || ! defined $data->{'uid'};

    # this means what was done with a user/group: added/edited/deleted
    my $action = $config->{"modified"} || "";

    #y2internal(Dumper($config));
    #y2internal(Dumper($data));
    
    cond_IMAP_OP($data->{'uid'}, "delete") if $action eq "deleted";
    
    y2internal ("WriteBefore Mail called");
    return;
}

# what should be done after user is finally written to LDAP
BEGIN { $TYPEINFO{Write} = ["function", "boolean", "any", "any"];}
sub Write {

    my $self	= shift;
    my $config	= $_[0];
    my $data	= $_[1];

    # this means what was done with a user: added/edited/deleted
    my $action = $config->{"modified"} || "";
    y2internal ("Write Mail called");
    return;
}
1
# EOF
