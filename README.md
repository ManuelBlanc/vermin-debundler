# Vermin Debundler

Vermin Debundler is an utility to inspect the Stingray bundle files used in Vermintide 1 and 2.

## Usage

```
Usage: vtd [options..] verb [args..]

Options:
    -g game             Select the game bundle version.
    -b path             Base path for commands that generate files.
    -l file             Load a hash lookup file. Can be repeated.
    -n name             Load a hash lookup file. Can be repeated.
    -v                  Enable debug output.
Commands:
    dict                Print the hash lookup dictionary.
    help                Show this help.
    index               List the contents of a bundle.
    extract [file]      Extract a file.
```

## Authors

+ [ManuelBlanc](https://github.com/ManuelBlanc)


## Acknowledgements

Although this software has been written from scratch, it is based on the great work of the [BundleReader](https://github.com/griffin02/BundleReaderBetaRelease) team:

+ [IamLupo](https://github.com/IamLupo)
+ [Aussiemon](https://github.com/Aussiemon)
+ [Griffin02](https://github.com/griffin02)

Furthermore, [MurmurHash2](https://github.com/aappleby/smhasher/blob/master/src/MurmurHash2.cpp) has been written by Austin Appleby.


## License

See the [LICENSE](./LICENSE) file.
