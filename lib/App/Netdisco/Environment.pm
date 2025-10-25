package App::Netdisco::Environment;

use strict;
use warnings;

use File::ShareDir 'dist_dir';
use Path::Class;
use FindBin;

BEGIN {
  # 如果DANCER_APPDIR未设置或配置文件不存在，则自动设置环境变量
  if (not($ENV{DANCER_APPDIR} || '') or not -f file($ENV{DANCER_APPDIR}, 'config.yml')) {

    FindBin::again();
    my $me   = File::Spec->catfile($FindBin::RealBin, $FindBin::RealScript);
    my $uid  = (stat($me))[4] || 0;
    my $home = ($ENV{NETDISCO_HOME} || (getpwuid($uid))[7] || $ENV{HOME});
    $ENV{NETDISCO_HOME} ||= $home;

    # 设置netdisco-do命令路径
    $ENV{NETDISCO_DO} ||= File::Spec->catfile($FindBin::RealBin, 'netdisco-do');

    my $auto = dir(dist_dir('App-Netdisco'))->absolute;

    # 设置Dancer应用目录和配置目录
    $ENV{DANCER_APPDIR}  ||= $auto->stringify;
    $ENV{DANCER_CONFDIR} ||= $auto->stringify;

    # 设置环境目录（优先使用用户目录，否则使用默认目录）
    my $test_envdir = dir($home, 'environments')->stringify;
    $ENV{DANCER_ENVDIR} ||= (-d $test_envdir ? $test_envdir : $auto->subdir('environments')->stringify);

    # 设置Dancer环境为部署模式
    $ENV{DANCER_ENVIRONMENT} ||= 'deployment';
    $ENV{PLACK_ENV}          ||= $ENV{DANCER_ENVIRONMENT};

    # 设置公共资源目录和视图目录
    $ENV{DANCER_PUBLIC} ||= $auto->subdir('public')->stringify;
    $ENV{DANCER_VIEWS}  ||= $auto->subdir('views')->stringify;
  }

  {
    # Dancer 1使用有问题的YAML.pm模块
    # 这是一个全局的解决方案 - 可以只应用于Dancer::Config
    use YAML;
    use YAML::XS;
    no warnings 'redefine';
    *YAML::LoadFile = sub { goto \&YAML::XS::LoadFile };
  }
}

1;
