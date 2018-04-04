# Test262 Tools

## Runner script

To execute the Test262 Runner script, just call it through your shell.

```sh
./Tools/Scripts/test262-helpers/test262-runner.pl
```

If you're already in the `Tools/Scripts/test262-helpers` folder:

```
./test262-runner.pl
```

### Custom options

If you need to customize the execution, check out `test262-runner.pl --help` for extra commands.

| −−help, −h | Print a brief help message and exits. |
| −−child−processes, −p | Specify number of child processes. |
| −−test−only, −o | Specify one or more specific test262 directory of test to run. |
| −−t262, −t | Specify root test262 directory. |
| −−jsc, −j | Specify a custom JSC location. |
| −−debug, −d Use debug build of JSC. Can only use if −−jsc <path> is not provided. |
| −−verbose, −v | Verbose output for test results. |
| −−config, −c | Specify a config file. If not provided, script will load local `test262−config.yaml` |

## Import Script

WIP

## Development

The Test262 Runner script requires Perl 5.8.8, to install Perl 5.8.8, use [Perlbrew](https://perlbrew.pl/).

It’s not necessary to install Perl 5.8.8 to execute the runner script if you have a more recent version of Perl 5.x.x installed.

It's also not necessary to install or configure anything extra to execute the runner script. The script dependencies are also stored locally.

### Installing Perlbrew

#### Mac

`\curl -L https://install.perlbrew.pl | bash`

#### Linux (Debian derivative):

```
sudo apt-get install perlbrew
perlbrew init
```

### Loading Perlbrew

Append the following piece of code to the end of your ~/.bash_profile and start a
new shell, perlbrew should be up and fully functional from there:

`source ~/perl5/perlbrew/etc/bashrc`

### Installing Perl 5.8.8 through Perlbrew

#### Mac

`perlbrew install perl-5.8.8`

#### Linux

`perlbrew --notest install perl-5.8.8   # Perl 5.8.8 has some known compilation errors`

### Switching to Perl versions

```sh
perlbrew switch perl-5.8.8
perlbrew switch perl-5.27.6
...
```

### Install cpanminus and Carton

Install cpanminus and Carton to set and manage dependencies.

```
perlbrew install-cpanm
cpanm install Carton
```

### Installing dependencies through Carton

From the `Tools/Scripts/test262-helpes/` folder, run `carton install` to install dependencies from the `cpanfile`.

More documentation on the cpanfile [here](https://metacpan.org/pod/distribution/Module-CPANfile/lib/cpanfile.pod).

### Executing the script using Carton:

```
carton exec test262-runner.pl
```

### Loading dependencies without Carton

To run the script without Carton, prepend your script file with the following code:

```perl
use FindBin;
use Config;
use Encode;

BEGIN {
    $ENV{DBIC_OVERWRITE_HELPER_METHODS_OK} = 1;

    unshift @INC, ".";
    unshift @INC, "$FindBin::Bin/lib";
    unshift @INC, "$FindBin::Bin/local/lib/perl5";
    unshift @INC, "$FindBin::Bin/local/lib/perl5/$Config{archname}";

    $ENV{LOAD_ROUTES} = 1;
}
```
