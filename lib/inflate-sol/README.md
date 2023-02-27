# inflate-sol

An implementation of [Puff](https://github.com/madler/zlib/blob/master/contrib/puff) in Solidity. This decompresses a [DEFLATE](https://tools.ietf.org/html/rfc1951)-compressed data stream.

## Installing

TODO

## Usage

```solidity
pragma solidity >=0.8.0 <0.9.0;

import "./InflateLib.sol";

contract InflateLibTest {
    function puff(bytes calldata source, uint256 destlen)
        external
        pure
        returns (InflateLib.ErrorCode, bytes memory)
    {
        return InflateLib.puff(source, destlen);
    }
}
```
