# $Id:$
package rrdimage;
use strict;
use RRDs;
use POSIX;
use Image::Size;


# create and update rrd-based graphs, 
# returns: errmsg (or 0), img name, x, y
#
# args: imgdir, rrddir, maxage, forceregen (defaults to 0)
# name, imgname (defaults to name), type, label, mode (overview or day/week/month/year)
# extras (for type-specific parameters)
sub rrdimage_update
{
    my (%args)=@_;

    use Data::Dumper;

    my $extras=$args{extras};
    my ($errmsg,$x,$y)=(0,0,0);
    my $imgname = ($args{imgname}||$args{name})."-$args{type}-$args{mode}.png";
    my $fn = "$args{imgdir}/$imgname";
    my $fage=(stat($fn))[9];
    
    # not new enough or reload required
    if ($fage<time-$args{maxage} || $args{forceregen}) 
    {
	# type given as arg, tag: which rrdfile to use
	my %type2tag=("cpu"=>"cpustats",
								"load"=>"cpustats",
								"mem"=>"memory",
								"diskpc"=>"disks",
								"sensors"=>"sensors",
								"inet"=>"dsl",
								"linestatus"=>"dsl",
								"internode"=>"internode",
								"internodeflat"=>"internode",
								"if"=>"interfaces",
								"nfacct"=>"nfacct",
								"news"=>"newslog",
								"mail"=>"maillog",
								"mailrej"=>"maillog",
								"solar"=>"growatt",
	    );
	
	my $rrdf="$args{rrddir}/$args{name}-".$type2tag{$args{type}}.".rrd";
	

	# fixed args first
	my @rrdargs=($fn,
		     "-t", $args{label},
		     "-W",scalar(localtime),"-a","PNG");
	if ($args{mode} eq "overview")
	{
	    push @rrdargs,qw(-h 80 -w 250 -S 300 -s -36000);
	}
	else 
	{
	    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday)=localtime;
	    
	    push @rrdargs,qw(-h 200 -w 600 -s);
	    if ($args{mode} eq "day")
	    {
		# axis legend yucky by default
		push @rrdargs,(-30*3600,qw(-x HOUR:1:HOUR:6:HOUR:2:0:%-H),
			       'VRULE:'.(time-$sec-$min*60-$hour*3600).'#ff0000',
			       'VRULE:'.(time-$sec-$min*60-$hour*3600-86400).'#ff0000');
	    }
	    elsif ($args{mode} eq "week")
	    {
		push @rrdargs,(-8*86400,'-S',300,
			       'VRULE:'.(time-$sec-$min*60-$hour*3600-($wday-1)*86400).'#ff0000',
			       'VRULE:'.(time-$sec-$min*60-$hour*3600-($wday+6)*86400).'#ff0000');
	    }
	    elsif ($args{mode} eq "month")
	    {
		push @rrdargs,(-36*86400,'-S',7200,
			       'VRULE:'.(time-$sec-$min*60-$hour*3600-$mday*86400).'#ff0000',
			       'VRULE:'.mktime(0,0,0,1,$mon-1,$year).'#ff0000');
	    }
	    else
	    {
		push @rrdargs,(-396*86400,'-S',86400,
			       'VRULE:'.mktime(0,0,0,1,0,$year).'#ff0000',
			       'VRULE:'.mktime(0,0,0,1,0,$year-1).'#ff0000');
	    }
	}

	
	# type-dependent args next
	if ($args{type} eq "cpu")
	{
	    push @rrdargs,("-v","% CPU",
			   qw(-u 100 --rigid),
			   (map { "DEF:$_=$rrdf:$_:AVERAGE" } qw(user system nice idle)),
			   'CDEF:total=user,system,nice,idle,+,+,+',
			   'CDEF:a=user,total,/,100,*',
			   'CDEF:b=system,total,/,100,*',
			   'CDEF:c=nice,total,/,100,*',
			   'CDEF:d=idle,total,/,100,*',
			   'AREA:a#eacc00:user',
			   'GPRINT:a:MAX: max\:%3.0lf%%',
			   'GPRINT:a:AVERAGE: avg\:%3.0lf%%',
			   'GPRINT:a:LAST:  cur\:%3.0lf%%',
			   'COMMENT:\n',
			   'AREA:b#ea8f00:sys:STACK',
			   'GPRINT:b:MAX:  max\:%3.0lf%%',
			   'GPRINT:b:AVERAGE: avg\:%3.0lf%%',
			   'GPRINT:b:LAST:  cur\:%3.0lf%%',
			   'COMMENT:\n',
			   'AREA:c#ff3932:nice:STACK',
			   'GPRINT:c:MAX: max\:%3.0lf%%',
			   'GPRINT:c:AVERAGE: avg\:%3.0lf%%',
			   'GPRINT:c:LAST:  cur\:%3.0lf%%',
			   'COMMENT:\n');
	}
	elsif ($args{type} eq "load")
	{
	    push @rrdargs,(qw(-v Load -u 1.25 --right-axis 250:0
			  --right-axis-label),"# proc",
			   '--right-axis-format',"%4.0lf",
			   (map { "DEF:$_=$rrdf:$_:AVERAGE" } qw(one fifteen nproc)),
			   split(/\s*\n\s*/,
				 'CDEF:ns=nproc,250,/
	AREA:one#87CEEB:1m
	GPRINT:one:MAX:   max\: %3.2lf
	GPRINT:one:AVERAGE:avg\: %3.2lf
	GPRINT:one:LAST:cur\: %3.2lf
	COMMENT:\n
    LINE:fifteen#0000ff:15m
	GPRINT:fifteen:MAX:  max\: %3.2lf
	GPRINT:fifteen:AVERAGE:avg\: %3.2lf
	GPRINT:fifteen:LAST:cur\: %3.2lf
	COMMENT:\n
    LINE:ns#32CD32:#proc
	GPRINT:nproc:MAX:max\: %3.0lf
	GPRINT:nproc:AVERAGE: avg\: %3.0lf
	GPRINT:nproc:LAST: cur\: %3.0lf
	COMMENT:\n'));
	}
	elsif ($args{type} eq "mem")
	{
	    push @rrdargs,(qw(-v RAM -b 1024 --alt-autoscale-max -l 0),
			   (map { "DEF:$_=$rrdf:$_:AVERAGE" } qw(used free buffers cached swap)),
			   split(/\s*\n\s*/,'CDEF:cdeftot=used,free,buffers,cached,swap,+,+,+,+
AREA:used#eacc00:used
GPRINT:used:MAX:   max\: %8.2lf%s
GPRINT:used:AVERAGE: avg\: %8.2lf%s
GPRINT:used:LAST: cur\: %8.2lf%s\n
AREA:buffers#006400:buffers:STACK
GPRINT:buffers:MAX:max\: %8.2lf%s
GPRINT:buffers:AVERAGE: avg\: %8.2lf%s
GPRINT:buffers:LAST: cur\: %8.2lf%s\n
    AREA:cached#3cb371:cached:STACK
    GPRINT:cached:MAX: max\: %8.2lf%s
    GPRINT:cached:AVERAGE: avg\: %8.2lf%s
    GPRINT:cached:LAST: cur\: %8.2lf%s\n
    AREA:free#adff2f:free:STACK
    GPRINT:free:MAX:   max\: %8.2lf%s
    GPRINT:free:AVERAGE: avg\: %8.2lf%s
    GPRINT:free:LAST: cur\: %8.2lf%s\n
    AREA:swap#ff0000:swap:STACK
    GPRINT:swap:MAX:   max\: %8.2lf%s
    GPRINT:swap:AVERAGE: avg\: %8.2lf%s
    GPRINT:swap:LAST: cur\: %8.2lf%s
    LINE1:cdeftot#000001:
COMMENT:\n'));
	}
	elsif ($args{type} eq "diskpc")
	{
	    # needs extra arg: @disks (list of tags, used as labels)
	    my @disks=split(/\s+/,$extras->{disks});
	    my $maxlen=length((sort { length($b) <=> length($a) } (@disks))[0]);
	    my @colors=qw(ff4500 ffa500 ffd700 32cd32 4169e1 9370db); 
	    push @rrdargs,(qw(-u 100 --rigid -l 0),"-v","util %");
	
	    for my $i (0..$#disks)
	    {
		my $k="d$i";
		my $color=$colors[$i];
		my $name=$disks[$i];
		my $namedelta=1+$maxlen-length($name);
		my $spacer=" " x ($namedelta);
		
		push @rrdargs,("DEF:t$k=$rrdf:${name}_t:AVERAGE",
			       "DEF:u$k=$rrdf:${name}_u:AVERAGE",
			       "CDEF:$k=u$k,t$k,/,100,*",
			       "CDEF:f$k=t$k,u$k,-",
			       "LINE:$k#$color:$name",
			       "COMMENT:$spacer",
			       "GPRINT:t$k:LAST:tot\\: %4.0lf%s",
			       "GPRINT:f$k:LAST:free\\: %4.0lf%s",
			       "GPRINT:$k:LAST:used\\: %3.0lf%%",
			       'COMMENT:\\n');
	    }
	}
	elsif ($args{type} eq "sensors")
	{
	    # extra args: cpu=>"cpuX cpuY", board=>"ds ds",
	    #  disks=>"ds ds" fanscale=>N, fans=>"ds ds" labels=>"label \t label \t" (disks, dann fans)
	    # cpufront=>0/1 (draw board temp then cpu, for board>cpu)
	    # fanpercent=>0/1 (rpm or percent)
	    my @labels=split(/\t/,$extras->{labels});
	    my @fans=split(/\s+/,$extras->{fans});
	    my @disks=split(/\s+/,$extras->{disks});

	    my $maxlen=length((sort { length($b) <=> length($a) } (@labels,"cpu","case"))[0]);
	    my @colors=qw(ffd700 ff8c00 b22222); # disks
	    my @fcolors=qw(ff00ff 008000 98fb98); # fans
	    
	    push @rrdargs,(qw(-u 60 -l 25),"-v","deg C");
	    if ($extras->{fanscale})
	    {
		push @rrdargs,("--right-axis",$extras->{fanscale}.":0",
			       "--right-axis-label",($extras->{fanpercent}?"%":"rpm"),
			       qw(--right-axis-format %4.0lf));
	    }
	    my (@cputemp,@casetemp);
	    
	    # cpus: collate oder einzige
	    if (my @cpus=split(/\s+/,$extras->{cpu}))
	    {
		if (@cpus>1)
		{
		    push @cputemp,((map { "DEF:$_=$rrdf:$_:AVERAGE" } (@cpus)),
				   "CDEF:c=".join(",",@cpus).",".@cpus.",AVG");
		}
		else
		{
		    push @rrdargs,"DEF:c=$rrdf:$cpus[0]:AVERAGE";
		}
		
		my $namedelta=1+$maxlen-length('cpu');
		my $spacer=" " x ($namedelta);
		push @cputemp,('AREA:c#0000CD:cpu',
			       "COMMENT:$spacer",
			       'GPRINT:c:MIN:min\: %4.1lf',
			       'GPRINT:c:MAX:max\: %4.1lf',
			       'GPRINT:c:AVERAGE:avg\: %4.1lf deg',
			       'COMMENT:\n');
	    }
	    # board/case/other temp sensors
	    if (my $bt=$extras->{board})
	    {
		my $namedelta=1+$maxlen-length('case');
		my $spacer=" " x ($namedelta);
		
		# collate oder einziger sensor?
		if (my @temps=split(/\s+/,$bt))
		{
		    if (@temps>1)
		    {
			push @casetemp,((map { "DEF:$_=$rrdf:$_:AVERAGE" } (@temps)),
					"CDEF:b=".join(",",@temps).",".@temps.",AVG");
		    }
		    else
		    {
			push @rrdargs,"DEF:b=$rrdf:$bt:AVERAGE";
		    }
		}
		push @casetemp,('AREA:b#afeeee:case',
				"COMMENT:$spacer",
				'GPRINT:b:MIN:min\: %4.1lf',
				'GPRINT:b:MAX:max\: %4.1lf',
				'GPRINT:b:AVERAGE:avg\: %4.1lf deg',
				'COMMENT:\n');
	    }

	    # heffalump nf96 board: system temp higher than cpu, so need to reorder
	    if ($extras->{cpufront})
	    {
		push @rrdargs,@casetemp,@cputemp;
	    }
	    else
	    {
		push @rrdargs,@cputemp,@casetemp;
	    }
	    
	    # disk(s)
	    for my $i (0..$#disks)
	    {
		my $l=shift @labels;
		my $namedelta=1+$maxlen-length($l);
		my $spacer=" " x ($namedelta);
		
		push @rrdargs,("DEF:t$i=$rrdf:$disks[$i]:AVERAGE",
			       "LINE1:t$i#$colors[$i]:$l",
			       "COMMENT:$spacer",
			       "GPRINT:t$i:MIN:min\\: %4.1lf",
			       "GPRINT:t$i:MAX:max\\: %4.1lf",
			       "GPRINT:t$i:AVERAGE:avg\\: %4.1lf deg",
			       'COMMENT:\n');
	    }
	    # finally, fans
	    for my $i (0..$#fans)
	    {
		my $l=shift @labels;
		my $namedelta=1+$maxlen-length($l);
		my $spacer=" " x ($namedelta);
		
		push @rrdargs,"DEF:f$i=$rrdf:$fans[$i]:AVERAGE";
		if ($extras->{fanscale})
		{
		    push @rrdargs,("CDEF:sf$i=f$i,$extras->{fanscale},/",
				   "LINE:sf$i#$fcolors[$i]:$l");
		}
		else
		{
		    push @rrdargs,"LINE:f$i#$fcolors[$i]:$l";
		}
		push @rrdargs,("COMMENT:$spacer",
			       "GPRINT:f$i:MIN:min\\: %4.0lf",
			       "GPRINT:f$i:MAX:max\\: %4.0lf",
			       "GPRINT:f$i:AVERAGE:avg\\: %4.0lf "
			       .($extras->{fanpercent}?"%%":"rpm"),
			       'COMMENT:\n');
	    }
	}
	elsif ($args{type} eq "inet")
	{
	    my $xrrdf="$args{rrddir}/$args{name}-iptables.rrd";
	    push @rrdargs,(qw(-v bit/s),
			   (map { "DEF:$_=$rrdf:$_:AVERAGE" } (qw(down up downsync upsync))),
			   "DEF:dropped=$xrrdf:logdrop:AVERAGE",
			   split(/\s*\n\s*/, 'CDEF:upneg=0,up,-
    AREA:down#98fb98:download
    GPRINT:downsync:LAST:a/v\: %5.1lf%s
    GPRINT:down:MAX:max\: %5.1lf%s
    GPRINT:down:AVERAGE:avg\: %5.1lf%s
    GPRINT:down:LAST:cur\: %5.1lf%s
    COMMENT:\n
    LINE1:down#58bb58:
    AREA:dropped#FF4500:firewall
    GPRINT:dropped:MAX:             max\: %5.1lf%s
    GPRINT:dropped:AVERAGE:avg\: %5.1lf%s
    GPRINT:dropped:LAST:cur\: %5.1lf%s
    COMMENT:\n
    AREA:upneg#48d1cc:upload
    GPRINT:upsync:LAST:  a/v\: %5.1lf%s
    GPRINT:up:MAX:max\: %5.1lf%s
    GPRINT:up:AVERAGE:avg\: %5.1lf%s
    GPRINT:up:LAST:cur\: %5.1lf%s
    COMMENT:\n
    LINE1:upneg#08918c:
CDEF:axis=up,UN,0,0,IF
LINE:axis#808080:
'
			   ));
	}
	elsif ($args{type} eq "linestatus")
	{
	    push @rrdargs,(qw(-v bit/s -l 0 --right-axis .004:0 --right-axis-format %4.0lf),
			   "--right-axis-label","error secs",
			   (map { "DEF:$_=$rrdf:$_:AVERAGE" } (qw(down up downsync upsync downmargin upmargin resets errorsecs))),
			   split(/\s*\n\s*/,'CDEF:es=errorsecs,250,*
    LINE1:downsync#32cd32:down sync
    GPRINT:downsync:MAX:max\: %5.1lf%s
    GPRINT:downsync:AVERAGE:avg\: %5.1lf%s
    GPRINT:downsync:LAST:cur\: %5.1lf%s
    COMMENT:\n
    LINE1:upsync#6495ed:up sync
    GPRINT:upsync:MAX:  max\: %5.1lf%s
    GPRINT:upsync:AVERAGE:avg\: %5.1lf%s
    GPRINT:upsync:LAST:cur\: %5.1lf%s
    COMMENT:\n
    GPRINT:upmargin:LAST:margin up\: %4.1lf
    GPRINT:downmargin:LAST:margin dn\: %4.1lf
    COMMENT:\n
    AREA:es#FFd700:errors
    GPRINT:errorsecs:LAST:cur\: %3.0lf
    GPRINT:resets:LAST:resets\: %3.0lf
    COMMENT:\n
    LINE:es#bfa700:'));
     
	}
	elsif ($args{type} eq "internode")
	{
		# internode normal
		push @rrdargs,(qw(-v bytes -l 0),
									 (map { "DEF:$_=$rrdf:$_:AVERAGE" } (qw(quota traffic))),
									 split(/\s*\n\s*/,'CDEF:remain=quota,traffic,-
    CDEF:remainpc=1,traffic,quota,/,-,100,*
    LINE1:quota#ff4500:quota
    GPRINT:quota:LAST:%7.2lf%s
    COMMENT:\n
    AREA:traffic#1e90ff:used
    GPRINT:traffic:LAST: %7.2lf%s
    COMMENT:\n
    GPRINT:remainpc:LAST:remaining\:   %3.0lf%%
    COMMENT:\n'));
	}
	elsif  ($args{type} eq "internodeflat")
	{
		# flat: only traffic, quota is present but 0

		push @rrdargs,(qw(-v bytes -l 0),
									 "DEF:traffic=$rrdf:traffic:AVERAGE",
									 split(/\s*\n\s*/,'AREA:traffic#1e90ff:used
    GPRINT:traffic:LAST: %7.2lf%s
    COMMENT:\n'));
	}
	elsif ($args{type} eq "if")
	{
	    # extras: if=>"dsname dsname" (not given: main_i/main_o labels=>"in \t out" (if not given: "in out")
	    # and: firewall=>"dsname"
	    my $xrrdf="$args{rrddir}/$args{name}-iptables.rrd";
	    my @labels=split(/\t/,$extras->{labels}||"in\tout\tfirewall");
	    my @names=split(/\s+/,$extras->{"if"}||"main_i main_o");
	    push @names,$extras->{firewall} if ($extras->{firewall});

	    my $maxlen=length((sort { length($b) <=> length($a) } (@labels))[0]);
	    my $ispacer=" " x (1+$maxlen-length($labels[0]));
	    my $ospacer=" " x (1+$maxlen-length($labels[1]));
	    my $fspacer=" " x (1+$maxlen-length($labels[2]));
	    
	    push @rrdargs,(qw(-v bytes/s),
			   "DEF:in=$rrdf:$names[0]:AVERAGE",
			   "DEF:out=$rrdf:$names[1]:AVERAGE",
			   'CDEF:outneg=0,out,-',
			   "AREA:in#98fb98:$labels[0]",
			   "COMMENT:$ispacer",
			   'GPRINT:in:MAX:max\: %6.1lf%s',
			   'GPRINT:in:AVERAGE:avg\: %6.1lf%s',
			   'GPRINT:in:LAST:cur\: %6.1lf%s',
			   'COMMENT:\n',
			   'LINE1:in#58bb58:');
	    push @rrdargs,("DEF:firewall=$xrrdf:$names[2]:AVERAGE",
			   "AREA:firewall#FF4500:$labels[2]",
			   "COMMENT:$fspacer",
			   'GPRINT:firewall:MAX:max\: %6.1lf%s',
			   'GPRINT:firewall:AVERAGE:avg\: %6.1lf%s',
			   'GPRINT:firewall:LAST:cur\: %6.1lf%s',
			   'COMMENT:\n')
		if ($extras->{firewall});
	    push @rrdargs, ("AREA:outneg#48d1cc:$labels[1]",
			    "COMMENT:$ospacer",
			    'GPRINT:out:MAX:max\: %6.1lf%s',
			    'GPRINT:out:AVERAGE:avg\: %6.1lf%s',
			    'GPRINT:out:LAST:cur\: %6.1lf%s',
			    'COMMENT:\n',
			    'LINE1:outneg#08918c:',
			    'CDEF:axis=in,UN,0,0,IF',
			    'LINE:axis#808080:');
	}
	elsif ($args{type} eq "nfacct")
	{
	    # extras: if=>"dsname dsname" (not given: main_i/main_o),
	    #  labels=>"in \t out" (if not given: "in out")
	    # and: firewall=>"dsname"
	    my $xrrdf="$args{rrddir}/$args{name}-nfacct.rrd";
	    my @labels=split(/\t/,$extras->{labels}||"in\tout\tfirewall");
	    my @names=split(/\s+/,$extras->{"if"}||"main_i main_o");
	    push @names,$extras->{firewall} if ($extras->{firewall});
	    
	    my $maxlen=length((sort { length($b) <=> length($a) } (@labels))[0]);
	    my $ispacer=" " x (1+$maxlen-length($labels[0]));
	    my $ospacer=" " x (1+$maxlen-length($labels[1]));
	    my $fspacer=" " x (1+$maxlen-length($labels[2]));
	    
	    push @rrdargs,(qw(-v bytes/s),
			   "DEF:in=$rrdf:$names[0]:AVERAGE",
			   "DEF:out=$rrdf:$names[1]:AVERAGE",
			   'CDEF:outneg=0,out,-',
			   "AREA:in#98fb98:$labels[0]",
			   "COMMENT:$ispacer",
			   'GPRINT:in:MAX:max\: %6.1lf%s',
			   'GPRINT:in:AVERAGE:avg\: %6.1lf%s',
			   'GPRINT:in:LAST:cur\: %6.1lf%s',
			   'COMMENT:\n',
			   'LINE1:in#58bb58:');
	    push @rrdargs,("DEF:firewall=$xrrdf:$names[2]:AVERAGE",
			   "AREA:firewall#FF4500:$labels[2]",
			   "COMMENT:$fspacer",
			   'GPRINT:firewall:MAX:max\: %6.1lf%s',
			   'GPRINT:firewall:AVERAGE:avg\: %6.1lf%s',
			   'GPRINT:firewall:LAST:cur\: %6.1lf%s',
			   'COMMENT:\n')
		if ($extras->{firewall});
	    push @rrdargs, ("AREA:outneg#48d1cc:$labels[1]",
			    "COMMENT:$ospacer",
			    'GPRINT:out:MAX:max\: %6.1lf%s',
			    'GPRINT:out:AVERAGE:avg\: %6.1lf%s',
			    'GPRINT:out:LAST:cur\: %6.1lf%s',
			    'COMMENT:\n',
			    'LINE1:outneg#08918c:',
			    'CDEF:axis=in,UN,0,0,IF',
			    'LINE:axis#808080:');
	}
	elsif ($args{type} eq "news")
	{
	    push @rrdargs,(qw(-v articles/h),
			   (map { ("DEF:x$_=$rrdf:$_:AVERAGE","CDEF:$_=x$_,3600,*") } (qw(in out refused))),
			   split(/\s*\n\s*/,'AREA:in#98fb98:in:
    GPRINT:in:MIN: min\: %4.0lf
    GPRINT:in:MAX:max\: %4.0lf
    GPRINT:in:AVERAGE:avg\: %4.0lf
    COMMENT:\n
    LINE:in#58bb58:
    AREA:refused#ff4500:ref:STACK
    GPRINT:refused:MIN:min\: %4.0lf
    GPRINT:refused:MAX:max\: %4.0lf
    GPRINT:refused:AVERAGE:avg\: %4.0lf
    COMMENT:\n
    CDEF:axis=in,UN,0,0,IF
    LINE:axis#808080:
    CDEF:nout=xout,-3600,*
    AREA:nout#48d1cc:out
    GPRINT:out:MIN:min\: %4.0lf
    GPRINT:out:MAX:max\: %4.0lf
    GPRINT:out:AVERAGE:avg\: %4.0lf
    COMMENT:\n
    LINE:nout#08918c:'));
	}
	elsif ($args{type} eq "mail")
	{
	    push @rrdargs,(qw(-v mails/hr),
			   (map { ("DEF:x$_=$rrdf:$_:AVERAGE","CDEF:$_=x$_,3600,*") } (qw(lightspam badspam in out virus))),
			   split(/\s*\n\s*/,'CDEF:nout=0,out,-
   AREA:in#98fb98:in
    GPRINT:in:MIN:     min\: %6.1lf
    GPRINT:in:MAX:max\: %6.1lf
    GPRINT:in:AVERAGE:avg\: %6.1lf
    COMMENT:\n
    LINE:in#58bb58:
    AREA:lightspam#f08080:spam:STACK
    GPRINT:lightspam:MIN:   min\: %6.1lf
    GPRINT:lightspam:MAX:max\: %6.1lf
    GPRINT:lightspam:AVERAGE:avg\: %6.1lf
    COMMENT:\n
    AREA:virus#FF7F50:virus:STACK
    GPRINT:virus:MIN:  min\: %6.1lf
    GPRINT:virus:MAX:max\: %6.1lf
    GPRINT:virus:AVERAGE:avg\: %6.1lf
    COMMENT:\n
    AREA:badspam#dc133c:badspam:STACK
    GPRINT:badspam:MIN:min\: %6.1lf
    GPRINT:badspam:MAX:max\: %6.1lf
    GPRINT:badspam:AVERAGE:avg\: %6.1lf
    COMMENT:\n
    AREA:nout#48d1cc:out
    GPRINT:out:MIN:    min\: %6.1lf
    GPRINT:out:MAX:max\: %6.1lf
    GPRINT:out:AVERAGE:avg\: %6.1lf
    COMMENT:\n
    LINE:nout#08918c:
    CDEF:axis=in,UN,0,0,IF
    LINE:axis#808080:'));
	}
	elsif ($args{type} eq "mailrej")
	{
	    push @rrdargs,(qw(-v mails/m),
			   (map { ("DEF:$_=$rrdf:$_:AVERAGE") } (qw(lightspam badspam in virus tempfail early))),
			   'CDEF:acc=lightspam,badspam,in,virus,+,+,+,60,*',
			   'CDEF:nacc=0,acc,-',
			   'CDEF:stempfail=tempfail,60,*',
			   'CDEF:searly=early,60,*',
			   split(/\s*\n\s*/,'AREA:nacc#98fb98:acc/late
    GPRINT:acc:MIN: min\: %5.1lf
    GPRINT:acc:MAX:max\: %5.1lf
    GPRINT:acc:AVERAGE:avg\: %5.1lf
    COMMENT:\n
    LINE1:nacc#58bb58:
    AREA:searly#ffd700:early rej:
    GPRINT:searly:MIN:min\: %5.1lf
    GPRINT:searly:MAX:max\: %5.1lf
    GPRINT:searly:AVERAGE:avg\: %5.1lf
    COMMENT:\n
    AREA:stempfail#ff4500:temp rej:STACK
    GPRINT:stempfail:MIN: min\: %5.1lf
    GPRINT:stempfail:MAX:max\: %5.1lf
    GPRINT:stempfail:AVERAGE:avg\: %5.1lf
CDEF:axis=in,UN,0,0,IF
LINE:axis#808080:
    COMMENT:\n'));
	}
	elsif ($args{type} eq "solar")
	{
	    my $rightscale=1/250.0;
	    # solar elev and energy: calc and graph daily maxes for month, year mode
	    my $maxmode=($args{mode} eq "month" or $args{mode} eq "year")?"MAX:step=86400":"AVERAGE";
	    
	    push @rrdargs,(qw(-v Watt -u 1300 --right-axis),$rightscale.":0",
			   qw(--right-axis-label kWh --right-axis-format %3.1lf),
			   "DEF:relev=$args{rrddir}/heffalump-sun_elevation.rrd:elevation:$maxmode",
			   "DEF:rexp=$args{rrddir}/heffalump-sun_exposure.rrd:exposure:AVERAGE",
			   "CDEF:elev=relev,0,MAX,".(1500/90.0).",*",
			   "DEF:rawtoday=$rrdf:etoday:$maxmode",
			   "CDEF:etoday=rawtoday,".(1/$rightscale).",*",
			   "CDEF:exp=rexp,".(1/$rightscale).",*",
			   "AREA:etoday#98fb98:energy",
			   "LINE1:etoday#58bb58:",
			   'GPRINT:rawtoday:MAX:  max\: %6.1lf',
			   'GPRINT:rawtoday:AVERAGE:avg\: %6.1lf',
			   'GPRINT:rawtoday:LAST:now\: %6.1lf kWh',
			   'COMMENT:\n',
			   "DEF:pnow=$rrdf:gridpower:AVERAGE",
			   "LINE1:pnow#1e90ff:output",
			   'GPRINT:pnow:MAX:  max\: %6.1lf',
			   'GPRINT:pnow:AVERAGE:avg\: %6.1lf',
			   'GPRINT:pnow:LAST:now\: %6.1lf Watt',
			   'COMMENT:\n');
	    push @rrdargs,("LINE:exp#ee82ee:exposure",
			   'GPRINT:rexp:MAX:max\: %6.1lf',
			   'GPRINT:rexp:AVERAGE:avg\: %6.1lf',
			   'GPRINT:rexp:LAST:-1d\: %6.1lf kWh/m2',
			   'COMMENT:\n') if ($args{mode} eq "week" 
					     or $args{mode} eq "month" or $args{mode} eq "year");
	    push @rrdargs,("LINE:elev#ff8c00:elev",
			   'GPRINT:relev:MAX:    max\: %6.1lf deg',
			   'COMMENT:\n',
	    );
	}

	@rrdargs=grep(!/^(G?PRINT|COMMENT)/i, @rrdargs) 
	    if ($args{mode} eq "overview"); # no text for previews

	
	(undef,$x,$y)=RRDs::graph(@rrdargs);
	$errmsg = RRDs::error || 0;
    }
    else
    {
	($x, $y) = imgsize($fn);
    }
    return ($errmsg, $imgname, $x, $y);
}

1;


