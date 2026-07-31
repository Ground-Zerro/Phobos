# Building, Running, and Developing

### Building

Windows 10 64-bit or Windows Server 2019, and Git for Windows is required. The build script will take care of downloading, verifying, and extracting the right versions of the various dependencies:

```text
C:\Projects> git clone https://git.zx2c4.com/wireguard-windows
C:\Projects> cd wireguard-windows
C:\Projects\phobos-windows> build
```

### Running

After you've built the application, run `amd64\phobos.exe` or `x86\phobos.exe` to install the manager service and show the UI.

```text
C:\Projects\phobos-windows> amd64\phobos.exe
```

The WireGuardNT driver that Phobos embeds requires a valid Microsoft signature to load, so on a development machine you may benefit from first installing an official [WireGuard for Windows](https://www.wireguard.com/install/) release, which registers a Microsoft-signed driver, and then subsequently running your own phobos.exe. Alternatively, you can craft your own installer using the `quickinstall.bat` script.

### Optional: Localizing

To translate the Phobos UI to your language:

1. Upgrade `resources.rc` accordingly. Follow the pattern.

2. Make a new directory in `locales\` containing the language ID:

  ```text
  C:\Projects\phobos-windows> mkdir locales\<langID>
  ```

3. Configure and run `build` to prepare initial `locales\<langID>\messages.gotext.json` file:

   ```text
   C:\Projects\phobos-windows> set GoGenerate=yes
   C:\Projects\phobos-windows> build
   C:\Projects\phobos-windows> copy locales\<langID>\out.gotext.json locales\<langID>\messages.gotext.json
   ```

4. Translate `locales\<langID>\messages.gotext.json`. See other language message files how to translate messages and how to tackle plural. Translations inherited from WireGuard for Windows are kept in place; new Phobos strings need to be filled in by hand.

5. Run `build` from the step 3 again, and test.

6. Repeat from step 4.

### Optional: Creating the Installer

The installer build script will take care of downloading, verifying, and extracting the right versions of the various dependencies:

```text
C:\Projects\phobos-windows> cd installer
C:\Projects\wireguard-windows\installer> build
```

### Optional: Signing Binaries

Add a file called `sign.bat` in the root of this repository with these contents, or similar:

```text
set SigningProvider=/sha1 1b3afa5e2a76bb51f00020002dccadb165689c33
set TimestampServer=http://timestamp.digicert.com
```

After, run the above `build` commands as usual, from a shell that has [`signtool.exe`](https://docs.microsoft.com/en-us/windows/desktop/SecCrypto/signtool) in its `PATH`, such as the Visual Studio 2017 command prompt.

### Alternative: Building from Linux

You must first have Mingw and ImageMagick installed.

```text
$ sudo apt install mingw-w64 imagemagick
$ git clone https://git.zx2c4.com/wireguard-windows
$ cd wireguard-windows
$ make
```

You can deploy the 64-bit build to an SSH host specified by the `DEPLOYMENT_HOST` environment variable (default "winvm") to the remote directory specified by the `DEPLOYMENT_PATH` environment variable (default "Desktop") by using the `deploy` target:

```text
$ make deploy
```

### [`wg(8)`](https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8) Support for Windows

The command line utility [`wg(8)`](https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8) works well on Windows. Being a Unix-centric project, it compiles with a Makefile and MingW:

```text
$ git clone https://git.zx2c4.com/wireguard-tools
$ PLATFORM=windows make -C wireguard-tools/src
$ stat wireguard-tools/src/wg.exe
```

It interacts with tunnels run by the main Phobos program.

When building on Windows, the aforementioned `build.bat` script takes care of building this.
