# Vermin Debundler

Vermin Debundler is an utility to inspect the Stingray bundle files used in Vermintide 1 and 2.

## Usage

```
Usage: main [options..] command [args..]

Options:
  -g, --game=1|2                   Select the game bundle version.
  -l, --lookup=PATH                Load a hash lookup file. Can be repeated.

Commands:
  dict                             Print the hash lookup dictionary.
  dump                             Dump some bundle information.
  help                             Show this help.
  list                             List the contents of a bundle.
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

See the [LICENSE](./LICENSE.md) file.

