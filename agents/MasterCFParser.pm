#
# $Id$
#
package MasterCFParser;
use strict;
use Data::Dumper;
no warnings 'redefine';

######################################################################################
# external (public functions/methods)
######################################################################################

sub new {
    my $this  = shift;
    my $path   = shift  || "/etc/postfix";
    my $logref = shift;

    if( defined $logref && $logref ne "" ) {
	*logger = $logref;
    }

    my $class = ref($this) || $this;
    my $self = {};
    $self->{cffile} = $path."/master.cf";

    bless $self, $class;
    return $self;
}

sub readMasterCF {
    my $this = shift;

    my $fd;
    my $cf = $this->{cffile};
    
    if( ! open($fd, $cf) ) {
	logger("unable to open $cf\n");
	return 1;
    }
    
    my @CFA = <$fd>;
    chomp(@CFA);
    close($fd);
    
    my $cfa;
    for(my $c=0; $c<scalar(@CFA); $c++ ) {
	my $line;
	if( $CFA[$c] =~ /^\s+/ ) {
	    logger("Syntax error in $cf, line ".($c+1)."\n");
	    return 1;
	}
	$line = $CFA[$c];
	while( defined $CFA[$c+1] && $CFA[$c+1] =~ /^\s+/ ) {
	    $line .= $CFA[++$c];
	}
	
	push @$cfa, line2service($line);
    }
    $this->{MCF} = $cfa;
    return 0;
}

sub writeMasterCF {
    my $this = shift;


    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return 1;
    }

    my $fd;
    my $cf = $this->{cffile};

    if( ! open($fd, ">$cf") ) {
	logger("unable to open $cf\n");
	return 1;
    }

    for(my $c=0; $c<scalar(@{$this->{MCF}}); $c++ ) {
	print $fd service2line($this->{MCF}->[$c])."\n";
    }

    close($fd);
    return 0;
}

sub deleteService {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return 1;
    }

    return 1 if ref($srv) ne "HASH";
    if( (! defined $srv->{service}) ||
	(! defined $srv->{command}) ) {
	logger("to delete a service, keys 'service' and 'command' are required\n");
	return 1;
    }

    for(my $c=0; $c<scalar(@{$this->{MCF}}); $c++ ) {
	next if ! defined $this->{MCF}->[$c]->{service};
	if( $this->{MCF}->[$c]->{service} eq $srv->{service} &&
	    $this->{MCF}->[$c]->{command} eq $srv->{command} ) {
	    delete $this->{MCF}->[$c];
	}
    }
}

sub getServiceByAttributes {
    my $this  = shift;
    my $fsrv   = shift;

    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return undef;
    }

    return undef if ref($fsrv) ne "HASH";

    my $retsrv;
    my $nrkeys = scalar(keys(%$fsrv));
    my $foundmatches = 0;
    foreach my $s ( @{$this->{MCF}} ) {
	next if defined $s->{comment};
	$foundmatches = 0;
	foreach my $fs ( keys %$fsrv ) {
	    $foundmatches++ if $fsrv->{$fs} eq $s->{$fs};
	}
	push @$retsrv, $s if $foundmatches == $nrkeys;
    }
    return $retsrv;
}

sub addService {
    my $this  = shift;
    my $srv   = shift;

    if( ! defined $this->{MCF} ) {
	logger("you have to call readMasterCF() first\n");
	return 1;
    }

    return 1 if not isValidService($srv);
    return 1 if $this->serviceExists($srv);

    if( $srv->{command} eq "pipe" ) {
	# if service has command pipe, then it is a an interface to
	# non-Postfix software, append at the end
	push @{$this->{MCF}}, $srv;
    } else {
	my $newcf;
	for(my $c=0; $c<scalar(@{$this->{MCF}}); $c++ ) {
	    if( defined $srv ) {
		my ($nc, $cmd) = $this->nextCommand($c);
		if( $cmd eq "pipe" ) {
		    push @$newcf, $srv;
		    while($c < $nc) {
			push @$newcf, $this->{MCF}->[$c++];
		    }
		    $srv = undef;
		}
	    }
	    push @$newcf, $this->{MCF}->[$c];
	}
	$this->{MCF} = $newcf;
    }
    return 0;
}

sub getRAWCF {
    my $this = shift;

    return $this->{MCF};
}


######################################################################################
# internal (private functions/methods)
######################################################################################

sub logger {
    my $line = shift || "";
    print STDERR "$line";
}

sub isValidService {
    my $srv = shift;

    return 0 if ref($srv) ne "HASH";
    return 0 if defined $srv->{comment};
    foreach my $k ( ( "service", "type", "private", "unpriv",
		      "chroot", "wakeup", "maxproc", "command" ) ) {
	if( (! defined $srv->{$k}) || $srv->{$k} eq "" ) {
	    logger("missing key <$k>\n");
	    return 0;
	}
    }
    return 1;
}

sub nextCommand {
    my $this = shift;
    my $pos  = shift;

    return ($pos, $this->{MCF}->[$pos]->{command}) if defined $this->{MCF}->[$pos]->{command};
    while( ! defined $this->{MCF}->[$pos]->{command} ) {
	$pos++;
    }
    
    return ($pos, $this->{MCF}->[$pos]->{command});
}

sub serviceExists {
    my $this  = shift;
    my $srv   = shift;

    foreach my $s ( @{$this->{MCF}} ) {
	next if ! defined $s->{service};
	if( $s->{service} eq $srv->{service} &&
	    $s->{command} eq $srv->{command} ) {
	    logger("service already exists in master.cf:\n".service2line($srv)."\n");
	    return 1;
	}
    }
    
    return 0;
}

sub service2line {
    my $srv = shift;

    my $line;
    if( defined $srv->{comment} ) {
	$line = $srv->{comment};
    } else {
	$line = 
	    sprintf("%-8s %-5s %-6s %-7s %-7s %-8s %-7s %s",
		    $srv->{service},
		    $srv->{type},
		    $srv->{private},
		    $srv->{unpriv},
		    $srv->{chroot},
		    $srv->{wakeup},
		    $srv->{maxproc},
		    $srv->{command}
		    );
	$line .= "\n  ".$srv->{options} if defined $srv->{options} && $srv->{options} ne "";
    }
    return $line;
}

sub line2service {
    my $line = shift;

    if( $line =~ /^\#/ ) {
	return { 'comment' => $line };
    } else {
	# service type  private unpriv  chroot  wakeup  maxproc command + args
	my ($service,$type,$private,$unpriv,$chroot,$wakeup,$maxproc,$command) =
	    $line =~ /^(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s+(.*)/;
	
	my $options = "";
	# command has additional options?
	if( $command =~ /\s/ ) {
	    ($command,$options) = $command =~ /^(.*?)\s+(.*)/;
	}
	
	return { 'service' => $service,
		 'type'    => $type,
		 'private' => $private,
		 'unpriv'  => $unpriv,
		 'chroot'  => $chroot,
		 'wakeup'  => $wakeup,
		 'maxproc' => $maxproc,
		 'command' => $command,
		 'options' => $options };
    }
}

1;
