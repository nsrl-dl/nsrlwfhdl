#!/usr/bin/perl -w
#
# Written to replace AppShelf for NSRL downloaded software acquisition 2019-07-29
#
# Wrapper around Python LOC bagging script
#
# Prerequisites on Ubuntu:
# https://github.com/LibraryOfCongress/bagit-python
# https://github.com/LibraryOfCongress/bagit-python/archive/master.zip
# sudo apt install python-pip
# pip install bagit
# ./bagit.py --help
# sha256sum
# zip
# perl -MCPAN -e install 'Config::Simple'
# perl -MCPAN -e install 'File::Copy::Vigilant'


use strict;
use Getopt::Std;
use Config::Simple;
# use File::Copy::Vigilant qw( copy );

use vars qw( $logFileName $opt_c $cfg $bagit_path $tbd_dir $stage_dir $dl_dir $football_dir $archive_dir $bagit_cmd $bagval_cmd $zip_cmd $sha_cmd $namePfx );

getopts("c:") or die "\nUsage: $0 [-c configfile]\n";

# find config file
($opt_c) or $opt_c = substr($0,0,-2) . "cfg"; # default to ThisProg.cfg
if (! -e "$opt_c") { die "\n#################################\n$0 : config file not found : $opt_c\n\tUsage: $0 -c config_file\n"; }

# load config file
$cfg = new Config::Simple($opt_c);

# load vars from config data
$bagit_path = $cfg->param("bagitPath");
$tbd_dir = $cfg->param("toBeBaggedDir");
$stage_dir = $cfg->param("isZippedDir");
$dl_dir = $cfg->param("downloadDir");
$football_dir = $cfg->param("footballDir");
$archive_dir = $cfg->param("archiveDir");
$sha_cmd = $cfg->param("sha256Cmd");

$namePfx = 1;

# 11. check that football is mounted and Cart directory is empty
(-d "$football_dir")  or die "\n################################\n\0 : cannot find the football at $football_dir\n";
(-d "$football_dir/Cart")  or die "\n################################\n\0 : cannot find the football Cart directory at $football_dir/Cart\n";
my $cartLs = `ls "$football_dir/Cart"`;
chomp $cartLs;
if (length($cartLs) > 0) { die "\n################################\n\0 : The football Cart is not empty, stopping work.\n"; }

# open the log file
my $now = time();
`mkdir ./logs`;
if (! -e "./logs") { die "$0 : cannot create directory for log files, stopping.\n"; }
$logFileName = "./logs/dl.$now.log";
open(FLOG,">>",$logFileName) or die "\n################################\n$0 : cannot open log file $logFileName for logging!\n"; 

# ensure directory structure is valid
if (! -e "$tbd_dir") { die "\n################################\n$0 : cannot find the directory with items to be bagged : $tbd_dir\n"; }
if (! -e "$stage_dir") { dot_message("mkdir -pv $stage_dir"); }
`mkdir -pv "$stage_dir"`;
if (! -e "$stage_dir") { minus_message("Could not make the staging directory $stage_dir - stopping."); close(FLOG); exit; }

# build some generic commands
$bagit_cmd = "$bagit_path/bagit.py  --sha1 --md5 --sha256 --log [ETID].log --external-identifier [ETID] [TBDDIR]/[ETID] ";
$bagval_cmd = "$bagit_path/bagit.py  --log [ETID].val.log --validate [TBDDIR]/[ETID] ";
$zip_cmd = 'cd [TBDDIR]/[ETID] ; zip -u -9 -pr -mT [STAGEDIR]/[ETID].zip . '; # and Unicode support, etc.

# 1.  identify ETID dirs
my $etid_ls = `ls $tbd_dir`;
chomp $etid_ls;
# bail if no directories
if (length($etid_ls) < 1) { die "\n################################\n$0 : no ETID directories found in $tbd_dir\n"; }

my @etids = split(/\n/,$etid_ls);

my $incompleteDirs = 0;


print FLOG "preparing to work on ETIDs\n" , join("\n", @etids) , "\n";

for my $e (@etids) {
	# 2. ensure dir contains 1 PDF, 1 PNG, 1 non-(PDF|PNG)
	my $contentLs = `ls $tbd_dir/$e`;
	chomp $contentLs;
	if ( ($contentLs =~ /\.pdf/i) && ($contentLs =~ /\.png/i) && ($contentLs =~ /\.[a-oq-z][a-ce-m-o-z][a-egh-z]/i) ) {
	    # normalize the PNG and PDF file names
	    my @pnames = split(/\n/,$contentLs);
	    for my $p (@pnames) {
		if (($p =~ /\.png$/i) || ($p =~ /\.pdf$/i)) {
	           my $normName = normalizeName($p);
                   dot_message( "renaming \"$tbd_dir/$e/$p\" \"$tbd_dir/$e/$normName\"");
                   my $ret = `mv -nv "$tbd_dir/$e/$p" "$tbd_dir/$e/$normName"`;
	        }
            }

	    # 4. make bag
	    my $b_cmd = $bagit_cmd;
	    $b_cmd =~ s/\[ETID\]/$e/g;   # sub in the actual values
	    $b_cmd =~ s/\[TBDDIR\]/$tbd_dir/g;
	    print FLOG "$b_cmd\n";
	    print "$b_cmd\n";
	    my $b_run =  `$b_cmd`;
	    # 5. test bag
	    my $v_cmd = $bagval_cmd;
	    $v_cmd =~ s/\[ETID\]/$e/g;
	    $v_cmd =~ s/\[TBDDIR\]/$tbd_dir/g;
	    print FLOG "$v_cmd\n";
	    print "$v_cmd\n";
	    my $v_run =  `$v_cmd`;
	    my $v_tail = `tail -n 1 "$e.val.log"`;
	    chomp $v_tail;
	    if ($v_tail =~ / is valid/) { 
		# 6. report on bag validity
	        dot_message("$e bag is valid."); 
	        # 7. zip bag
	        print FLOG "zip -mT $stage_dir/$e.zip $e.log $e.val.log\n";
	        print "zip -mT $stage_dir/$e.zip $e.log $e.val.log\n";
	        my $zl_run =  `zip -mT "$stage_dir/$e.zip" $e.log $e.val.log`;
	        my $z_cmd = $zip_cmd;
	        $z_cmd =~ s/\[ETID\]/$e/g;
	        $z_cmd =~ s/\[TBDDIR\]/$tbd_dir/g;
	        $z_cmd =~ s/\[STAGEDIR\]/$stage_dir/g;
	        print FLOG "$z_cmd\n";
	        print "$z_cmd\n";
	        my $z_run = `$z_cmd`;
		plus_message("$z_run");
		# 8. 9. test and report on zip status
		if (-e "$stage_dir/$e.zip") { 
			print FLOG "rmdir  $tbd_dir/$e\n" ;  
			print "rmdir  $tbd_dir/$e\n" ;  
			my $r_cmd =  `rmdir  "$tbd_dir/$e" `;  # remove empty bag directory
			chomp $r_cmd;
			if (length($r_cmd) > 1) { dot_message("$r_cmd"); }
			# print "rm -vf $dl_dir/$e^^* \n" ;  # 16. remove ETID files from Downloads dir
			$r_cmd =  `find "$dl_dir" -type f -name "$e^^*" -exec rm -vf "{}" \\; `;  # 16. remove ETID files from Downloads dir
			chomp $r_cmd;
			dot_message("$r_cmd");
		}
		else {
			minus_message("ERROR - Zip file not created for ETID $e");
		}
            }
	    else { minus_message( "$e bag is NOT valid."); } # NEXT here?
	}
	else {
		$incompleteDirs += 1;
	}
}

# 3. report count of dirs that could not be bagged
minus_message( "$incompleteDirs ETID directories in $tbd_dir could not be bagged.");

# check if everything could not be bagged
if ($incompleteDirs == scalar(@etids)) { close(FLOG); die "\n################################\nno valid ETID dirs were found in $tbd_dir\n"; }

# 10. hash zip files
dot_message( "cd $stage_dir ; $sha_cmd *.zip | sort > zip-hashes.txt");
# print `cd "$stage_dir" ; $sha_cmd *.zip > zip-hashes.txt`;
my $sha_run =  `cd "$stage_dir" ; $sha_cmd *.zip | sort > zip-hashes.txt`;

# check again to be paranoid
if (! -d "$football_dir/Cart")  { close(FLOG);  die "\n################################\n\0 : cannot find the football Cart directory at $football_dir/Cart\n";}


# 12. copy zips and manifest to Cart
my $stageLs = `ls $stage_dir`;
chomp $stageLs;
my @stageFiles = split(/\n/,$stageLs);
for my $f (@stageFiles) {
    my @p= split(/\//,$f); # get filename for later check
    # my $copyVal = copy( "$stage_dir/$f", "$football_dir/Cart", check => 'md5' ) ;    # by default, this will retry 2 times
    # if ( ( $copyVal == 0 ) || ( ! -e "$football_dir/Cart/$p[$#p]"))
    my $copyVal = `cp -vf "$stage_dir/$f" "$football_dir/Cart/" `;  
    if ( ( ! -e "$football_dir/Cart/$p[$#p]"))
    {
            minus_message( "$0 : copy issue with $stage_dir/$f -> $football_dir/Cart/$p[$#p]");
    }
    else {
            plus_message( "copy done for $football_dir/Cart/$p[$#p]");
    }
}

# make football files world writeable so gateway can delete them
 `cd "$football_dir/Cart" ;  chmod a+rw * `;

# 13. check hashes of zips on football against the manifest
my $zipTestRun = `cd "$football_dir/Cart" ; $sha_cmd *.zip | sort > /tmp/zipTestRun.txt ; diff -q /tmp/zipTestRun.txt "$football_dir/Cart/zip-hashes.txt" `;
# 14. report problems
if ($zipTestRun =~ /differ/i) { close(FLOG); die "\n################################\n$0 : hashes of Zip files in football Cart have been corrupted!\n#################################\n"; }
else { plus_message( "hashes match on the football!"); }

# 15. move zip files from staging dir to archive dir
print `mkdir -p "$archive_dir/$now"`;
if (! -e "$archive_dir/$now") { minus_message("Could not make the archive directory $archive_dir/$now - stopping."); close(FLOG); exit; }
dot_message( "moving zip files to archive location $archive_dir/$now ");
# print `mv -vf "$stage_dir/*" "$archive_dir/$now/"`;
my $cp_run = `cp -vpRP "$stage_dir/" "$archive_dir/$now/" && rm -rf "$stage_dir"/* `;
dot_message("$cp_run");

# 17. inform user
#print "\n*******************************************\nDone! Ejecting football drive.\n";
plus_message("Done! Ejecting football drive.");

# 18. eject drive
# print `$eject_cmd`;

close(FLOG);

exit;

# -----------------------
#
sub dot_message {
	my $text = shift;
	chomp $text;
	print FLOG "\n..........................................\n\t$text\n\t..................................\n";
	print "\n..........................................\n\t$text\n\t..................................\n";
	return;
}

sub plus_message {
	my $text = shift;
	chomp $text;
	print FLOG "\n++++++++++++++++++++++++++++++++++++++++++\n\t$text\n\t++++++++++++++++++++++++++++++++++\n";
	print "\n++++++++++++++++++++++++++++++++++++++++++\n\t$text\n\t++++++++++++++++++++++++++++++++++\n";
	return;
}

sub minus_message {
	my $text = shift;
	chomp $text;
	print FLOG "\n------------------------------------------\n\t$text\n\t----------------------------------\n";
	print "\n------------------------------------------\n\t$text\n\t----------------------------------\n";
	return;
}

# -----------------------

sub normalizeName {

        my $string = shift;
        # increment the prefix number
        $namePfx++;
        # create string for the file name prefix
        my $pfx = sprintf("%02d",$namePfx);
        # split the filename from the path
        my $path='';
        my $filename=$string;
        if ($string =~ /\//) {
            my $revPath = reverse($string);
            my @r = split(/\//,$revPath, 2);
            $path = reverse($r[1]);
            $filename = reverse($r[0]);
        }
        # normalize the filename
        $filename = lc($filename);
        $filename =~ s/[^a-z0-9\-\.\/]/_/g;
        $filename = $pfx . "_" . $filename;
        # if ($path ne '') { $string = "$path/$filename"; }
        # else { $string = $filename; }
        $string = $filename;
        print FLOG "\tNormalizedName is \"$string\"\n";
        return($string);

}


__END__

# /home/dwhite/Downloads/bagit-python-master/bagit.py  --sha1 --md5 --sha256 --log 90001.log --external-identifier 90002 /tmp/to-be-bagged/90002 ; date

