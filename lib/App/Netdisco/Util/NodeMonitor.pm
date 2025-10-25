package App::Netdisco::Util::NodeMonitor;

# 节点监控工具模块
# 提供节点监控和邮件通知功能

use App::Netdisco;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Net::Domain 'hostfqdn';
use App::Netdisco::Util::DNS qw/hostname_from_ip ipv4_from_hostname/;

use base 'Exporter';
our @EXPORT_OK = qw/
  monitor
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# 发送邮件通知
# 使用sendmail发送监控通知邮件
sub _email {
  my ($to, $subject, $body) = @_;
  return unless $to;
  my $domain = (hostfqdn || 'fqdn-undefined');

  my $SENDMAIL = '/usr/sbin/sendmail';
  open (SENDMAIL, "| $SENDMAIL -t") or die "Can't open sendmail at $SENDMAIL.\n";
    print SENDMAIL "To: $to\n";
    print SENDMAIL "From: Netdisco <netdisco\@$domain>\n";
    print SENDMAIL "Subject: $subject\n\n";
    print SENDMAIL $body;
  close (SENDMAIL) or die "Can't send letter. $!\n";
}

# 执行节点监控
# 处理监控条目并发送邮件通知
sub monitor {
  my $monitor = schema(vars->{'tenant'})->resultset('Virtual::NodeMonitor');

  # 遍历所有监控条目
  while (my $entry = $monitor->next) {
    # 构建邮件正文
    my $body = <<"end_body";
........ n e t d i s c o .........
  Node    : @{[$entry->mac]} (@{[$entry->why]})
  When    : @{[$entry->date]}
  Switch  : @{[$entry->name]} (@{[$entry->switch]})
  Port    : @{[$entry->port]} (@{[$entry->portname]})
  Location: @{[$entry->location]}

end_body

    debug sprintf ' monitor - reporting on %s at %s:%s',
      $entry->mac, $entry->name, $entry->port;
    # 发送邮件通知
    _email(
      $entry->cc,
      "Saw mac @{[$entry->mac]} (@{[$entry->why]}) on @{[$entry->name]} @{[$entry->port]}",
      $body
    );
  }
}

1;
