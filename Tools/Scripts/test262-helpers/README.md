To install Perl 5.8.8, use [Perlbrew](https://perlbrew.pl/)

Mac:

`\curl -L https://install.perlbrew.pl | bash`

Linux (Debian derivative):

```
sudo apt-get install perlbrew
perlbrew init
```

Append the following piece of code to the end of your ~/.bash_profile and start a
new shell, perlbrew should be up and fully functional from there:

`source ~/perl5/perlbrew/etc/bashrc`

Install Perl 5.8.8 through Perlbrew

Mac:

`perlbrew install perl-5.8.8`

Linux:

`perlbrew --notest install perl-5.8.8   # Perl 5.8.8 has some known compilation errors`

---

Switch to Perl 5.8.8

`perlbrew switch perl-5.8.8`

---

Install cpanminus

`perlbrew install-cpanm`

---

Install Carton

`cpanm install Carton`

---

If you don't have a cpanfile yet, create one (`touch cpanfile`) in this directory and run `carton install`. This will create a `cpanfile.snapshot` file and a `./local/` folder. **This folder should be ignored in the version control**.

If you need to save the installed dependencies, search for the use of `carton bundle` and `carton install --cached`, but do not export the created `local` folder.

You can specify a required Perl version in the cpanfile by adding the following line:

`requires 'perl', '5.8.8';`

---

To install dependencies from a `cpanfile`, run `carton install`.

More documentation on the cpanfile [here](https://metacpan.org/pod/distribution/Module-CPANfile/lib/cpanfile.pod).

---

Execute the code using Carton:

`carton exec test262-runner.pl`

Otherwise, to use Perl, prepend the script file with the following code:

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
