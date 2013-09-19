yum -y install git-all

echo 'THESE ARE MISSING IN SPEC'
yum -y install 'perl(Archive::Extract)'
yum -y install 'perl(Digest::SHA1)'
yum -y install 'perl(Archive::Tar)'

#exit 0
echo 'THESE ARE FROM SPEC'
yum -y install 'gettext'
yum -y install 'perl'
yum -y install 'perl(Module::Build)'
yum -y install 'perl(ExtUtils::Manifest)'
yum -y install 'perl(Test::More)'
yum -y install 'perl(Test::Pod)'
yum -y install 'perl(Test::Pod::Coverage)'
yum -y install 'perl(Module::Find)'
yum -y install 'perl(DateTime)'
yum -y install 'perl(IO::String)'
yum -y install 'perl(Locale::TextDomain)'
yum -y install 'perl(Module::Pluggable)'
yum -y install 'perl(Net::HTTPS)'
yum -y install 'perl(Net::SSL)'
yum -y install 'perl(Sys::Guestfs)'
yum -y install 'perl(Sys::Virt)'
yum -y install 'perl(Term::ProgressBar)'
yum -y install 'perl(URI)'
yum -y install 'perl(XML::DOM)'
yum -y install 'perl(XML::DOM::XPath)'
yum -y install 'perl(XML::Writer)'
yum -y install 'perl-Sys-Guestfs'
yum -y install 'perl-hivex'

echo 'THESE ARE FOR TESTING'

yum -y install 'rake'
yum -y install 'rubygem-minitest'
yum -y install 'rubygem-rake-compiler'
yum -y install 'rubygem-ruby-dbus'
yum -y install 'rubygem-glib2'
yum -y install 'hwloc'


