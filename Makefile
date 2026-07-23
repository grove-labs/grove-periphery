deploy-instant-converter-mainnet:
	forge script script/DeployInstantUsdcUsdsConverter.s.sol:DeployInstantUsdcUsdsConverterMainnet --rpc-url mainnet --account GROVE_MAINNET_DEPLOYER --broadcast --verify

# Before running, set CONVERTER_ADDRESS to the address logged by the deploy step.
# Either in .env (auto-loaded by forge) or inline: `CONVERTER_ADDRESS=0x... make verify-instant-converter-mainnet`.
verify-instant-converter-mainnet:
	forge script script/VerifyInstantUsdcUsdsConverter.s.sol:VerifyInstantUsdcUsdsConverterMainnet --rpc-url mainnet

