{ buildGoModule, fetchFromGitHub }:
buildGoModule {
  name = "drone-runner-docker";
  version = "1.8.1";

  src = fetchFromGitHub {
    owner = "drone-runners";
    repo = "drone-runner-docker";
    rev = "218235e4198f081d6796e97df21e9b4e8c99d0a0";
    sha256 = "sha256-3SbvnW+mCwaBCF77rAnDMqZRHX9wDCjXvFGq9w0E5Qw=";
  };

  vendorSha256 = "sha256-E18ykjQc1eoHpviYok+NiLaeH01UMQmigl9JDwtR+zo=";
}
