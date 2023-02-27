from web3 import Web3, WebsocketProvider

goerli = Web3(WebsocketProvider(""))
mainnet = Web3(WebsocketProvider(""))

abi = [
    {
        "inputs":[
            {
                "internalType":"uint255",
                "name":"_tokenId",
                "type":"uint256"
            }
        ],
        "name":"tokenURI",
        "outputs":[
            {
                "internalType":"string",
                "name":"",
                "type":"string"
            }
        ],
        "stateMutability":"view",
        "type":"function"
    }
]

testnet = goerli.eth.contract("0xA07c4c68dF3FFc40bfbe94e6E63e821FaE825d6F", abi=abi)
mainnet = mainnet.eth.contract("0x45C67B2b81067911dE611e11FC5c7a4605cA4162", abi=abi)

for i in range(1, 1112):
    print(f"checking metadata equality for token #{i}")

    testnet_data = testnet.functions.tokenURI(i).call()
    mainnet_data = mainnet.functions.tokenURI(i).call()

    assert testnet_data == mainnet_data, "data is not equal"

print("test passed!")