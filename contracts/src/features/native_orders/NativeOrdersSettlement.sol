// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2021 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

import "@0x/contracts-erc20/contracts/src/v06/IERC20TokenV06.sol";
import "@0x/contracts-erc20/contracts/src/v06/IEtherTokenV06.sol";
import "@0x/contracts-utils/contracts/src/v06/errors/LibRichErrorsV06.sol";
import "@0x/contracts-utils/contracts/src/v06/LibSafeMathV06.sol";
import "@0x/contracts-utils/contracts/src/v06/LibMathV06.sol";
import "../../errors/LibNativeOrdersRichErrors.sol";
import "../../fixins/FixinCommon.sol";
import "../../storage/LibNativeOrdersStorage.sol";
import "../../vendor/v3/IStaking.sol";
import "../interfaces/INativeOrdersEvents.sol";
import "../libs/LibSignature.sol";
import "../libs/LibNativeOrder.sol";
import "./NativeOrdersCancellation.sol";
import "./NativeOrdersProtocolFees.sol";


/// @dev Mixin for settling limit and RFQ orders.
abstract contract NativeOrdersSettlement is
    INativeOrdersEvents,
    NativeOrdersCancellation,
    NativeOrdersProtocolFees,
    FixinCommon
{
    using LibSafeMathV06 for uint128;
    using LibRichErrorsV06 for bytes;

    /// @dev Params for `_settleOrder()`.
    struct SettleOrderInfo {
        // Order hash.
        bytes32 orderHash;
        // Maker of the order.
        address maker;
        // Taker of the order.
        address taker;
        // Maker token.
        IERC20TokenV06 makerToken;
        // Taker token.
        IERC20TokenV06 takerToken;
        // Maker token amount.
        uint128 makerAmount;
        // Taker token amount.
        uint128 takerAmount;
        // Maximum taker token amount to fill.
        uint128 takerTokenFillAmount;
        // How much taker token amount has already been filled in this order.
        uint128 takerTokenFilledAmount;
    }

    /// @dev Params for `_fillLimitOrderPrivate()`
    struct FillLimitOrderPrivateParams {
        // The limit order.
        LibNativeOrder.LimitOrder order;
        // The order signature.
        LibSignature.Signature signature;
        // Maximum taker token to fill this order with.
        uint128 takerTokenFillAmount;
        // The order taker.
        address taker;
        // The order sender.
        address sender;
    }

    // @dev Fill results returned by `_fillLimitOrderPrivate()` and
    ///     `_fillRfqOrderPrivate()`.
    struct FillNativeOrderResults {
        uint256 ethProtocolFeePaid;
        uint128 takerTokenFilledAmount;
        uint128 makerTokenFilledAmount;
        uint128 takerTokenFeeFilledAmount;
    }

    constructor(
        address zeroExAddress,
        IEtherTokenV06 weth,
        IStaking staking,
        FeeCollectorController feeCollectorController,
        uint32 protocolFeeMultiplier,
        bytes32 greedyTokensBloomFilter
    )
        public
        NativeOrdersCancellation(zeroExAddress, greedyTokensBloomFilter)
        NativeOrdersProtocolFees(weth, staking, feeCollectorController, protocolFeeMultiplier)
    {
        // solhint-disable no-empty-blocks
    }

    /// @dev Fill a limit order. The taker and sender will be the caller.
    /// @param order The limit order. ETH protocol fees can be
    ///      attached to this call. Any unspent ETH will be refunded to
    ///      the caller.
    /// @param signature The order signature.
    /// @param takerTokenFillAmount Maximum taker token amount to fill this order with.
    /// @return takerTokenFilledAmount How much maker token was filled.
    /// @return makerTokenFilledAmount How much maker token was filled.
    function fillLimitOrder(
        LibNativeOrder.LimitOrder memory order,
        LibSignature.Signature memory signature,
        uint128 takerTokenFillAmount
    )
        public
        payable
        returns (uint128 takerTokenFilledAmount, uint128 makerTokenFilledAmount)
    {
        FillNativeOrderResults memory results =
            _fillLimitOrderPrivate(FillLimitOrderPrivateParams({
                order: order,
                signature: signature,
                takerTokenFillAmount: takerTokenFillAmount,
                taker: msg.sender,
                sender: msg.sender
            }));
        LibNativeOrder.refundExcessProtocolFeeToSender(results.ethProtocolFeePaid);
        (takerTokenFilledAmount, makerTokenFilledAmount) = (
            results.takerTokenFilledAmount,
            results.makerTokenFilledAmount
        );
    }

    /// @dev Fill an RFQ order for up to `takerTokenFillAmount` taker tokens.
    ///      The taker will be the caller. ETH should be attached to pay the
    ///      protocol fee.
    /// @param order The RFQ order.
    /// @param signature The order signature.
    /// @param takerTokenFillAmount Maximum taker token amount to fill this order with.
    /// @return takerTokenFilledAmount How much maker token was filled.
    /// @return makerTokenFilledAmount How much maker token was filled.
    function fillRfqOrder(
        LibNativeOrder.RfqOrder memory order,
        LibSignature.Signature memory signature,
        uint128 takerTokenFillAmount
    )
        public
        returns (uint128 takerTokenFilledAmount, uint128 makerTokenFilledAmount)
    {
        FillNativeOrderResults memory results =
            _fillRfqOrderPrivate(
                order,
                signature,
                takerTokenFillAmount,
                msg.sender
            );
        (takerTokenFilledAmount, makerTokenFilledAmount) = (
            results.takerTokenFilledAmount,
            results.makerTokenFilledAmount
        );
    }

    /// @dev Fill an RFQ order for exactly `takerTokenFillAmount` taker tokens.
    ///      The taker will be the caller. ETH protocol fees can be
    ///      attached to this call. Any unspent ETH will be refunded to
    ///      the caller.
    /// @param order The limit order.
    /// @param signature The order signature.
    /// @param takerTokenFillAmount How much taker token to fill this order with.
    /// @return makerTokenFilledAmount How much maker token was filled.
    function fillOrKillLimitOrder(
        LibNativeOrder.LimitOrder memory order,
        LibSignature.Signature memory signature,
        uint128 takerTokenFillAmount
    )
        public
        payable
        returns (uint128 makerTokenFilledAmount)
    {
        FillNativeOrderResults memory results =
            _fillLimitOrderPrivate(FillLimitOrderPrivateParams({
                order: order,
                signature: signature,
                takerTokenFillAmount: takerTokenFillAmount,
                taker: msg.sender,
                sender: msg.sender
            }));
        // Must have filled exactly the amount requested.
        if (results.takerTokenFilledAmount < takerTokenFillAmount) {
            LibNativeOrdersRichErrors.FillOrKillFailedError(
                getLimitOrderHash(order),
                results.takerTokenFilledAmount,
                takerTokenFillAmount
            ).rrevert();
        }
        LibNativeOrder.refundExcessProtocolFeeToSender(results.ethProtocolFeePaid);
        makerTokenFilledAmount = results.makerTokenFilledAmount;
    }

    /// @dev Fill an RFQ order for exactly `takerTokenFillAmount` taker tokens.
    ///      The taker will be the caller. ETH protocol fees can be
    ///      attached to this call. Any unspent ETH will be refunded to
    ///      the caller.
    /// @param order The RFQ order.
    /// @param signature The order signature.
    /// @param takerTokenFillAmount How much taker token to fill this order with.
    /// @return makerTokenFilledAmount How much maker token was filled.
    function fillOrKillRfqOrder(
        LibNativeOrder.RfqOrder memory order,
        LibSignature.Signature memory signature,
        uint128 takerTokenFillAmount
    )
        public
        returns (uint128 makerTokenFilledAmount)
    {
        FillNativeOrderResults memory results =
            _fillRfqOrderPrivate(
                order,
                signature,
                takerTokenFillAmount,
                msg.sender
            );
        // Must have filled exactly the amount requested.
        if (results.takerTokenFilledAmount < takerTokenFillAmount) {
            LibNativeOrdersRichErrors.FillOrKillFailedError(
                getRfqOrderHash(order),
                results.takerTokenFilledAmount,
                takerTokenFillAmount
            ).rrevert();
        }
        makerTokenFilledAmount = results.makerTokenFilledAmount;
    }

    /// @dev Fill a limit order. Internal variant. ETH protocol fees can be
    ///      attached to this call.
    /// @param order The limit order.
    /// @param signature The order signature.
    /// @param takerTokenFillAmount Maximum taker token to fill this order with.
    /// @param taker The order taker.
    /// @param sender The order sender.
    /// @return takerTokenFilledAmount How much maker token was filled.
    /// @return makerTokenFilledAmount How much maker token was filled.
    function _fillLimitOrder(
        LibNativeOrder.LimitOrder memory order,
        LibSignature.Signature memory signature,
        uint128 takerTokenFillAmount,
        address taker,
        address sender
    )
        public
        virtual
        payable
        onlySelf
        returns (uint128 takerTokenFilledAmount, uint128 makerTokenFilledAmount)
    {
        FillNativeOrderResults memory results =
            _fillLimitOrderPrivate(FillLimitOrderPrivateParams({
                order: order,
                signature: signature,
                takerTokenFillAmount: takerTokenFillAmount,
                taker: taker,
                sender: sender
            }));
        (takerTokenFilledAmount, makerTokenFilledAmount) = (
            results.takerTokenFilledAmount,
            results.makerTokenFilledAmount
        );
    }

    /// @dev Fill an RFQ order. Internal variant. ETH protocol fees can be
    ///      attached to this call. Any unspent ETH will be refunded to
    ///      `msg.sender` (not `sender`).
    /// @param order The RFQ order.
    /// @param signature The order signature.
    /// @param takerTokenFillAmount Maximum taker token to fill this order with.
    /// @param taker The order taker.
    /// @return takerTokenFilledAmount How much maker token was filled.
    /// @return makerTokenFilledAmount How much maker token was filled.
    function _fillRfqOrder(
        LibNativeOrder.RfqOrder memory order,
        LibSignature.Signature memory signature,
        uint128 takerTokenFillAmount,
        address taker
    )
        public
        virtual
        onlySelf
        returns (uint128 takerTokenFilledAmount, uint128 makerTokenFilledAmount)
    {
        FillNativeOrderResults memory results =
            _fillRfqOrderPrivate(
                order,
                signature,
                takerTokenFillAmount,
                taker
            );
        (takerTokenFilledAmount, makerTokenFilledAmount) = (
            results.takerTokenFilledAmount,
            results.makerTokenFilledAmount
        );
    }

    /// @dev Mark what tx.origin addresses are allowed to fill an order that
    ///      specifies the message sender as its txOrigin.
    /// @param origins An array of origin addresses to update.
    /// @param allowed True to register, false to unregister.
    function registerAllowedRfqOrigins(
        address[] memory origins,
        bool allowed
    )
        external
    {
        require(msg.sender == tx.origin,
            "NativeOrdersFeature/NO_CONTRACT_ORIGINS");

        LibNativeOrdersStorage.Storage storage stor =
            LibNativeOrdersStorage.getStorage();

        for (uint256 i = 0; i < origins.length; i++) {
            stor.originRegistry[msg.sender][origins[i]] = allowed;
        }

        emit RfqOrderOriginsAllowed(msg.sender, origins, allowed);
    }

    /// @dev Fill a limit order. Private variant. Does not refund protocol fees.
    /// @param params Function params.
    /// @return results Results of the fill.
    function _fillLimitOrderPrivate(FillLimitOrderPrivateParams memory params)
        private
        returns (FillNativeOrderResults memory results)
    {
        LibNativeOrder.OrderInfo memory orderInfo = getLimitOrderInfo(params.order);

        // Must be fillable.
        if (orderInfo.status != LibNativeOrder.OrderStatus.FILLABLE) {
            LibNativeOrdersRichErrors.OrderNotFillableError(
                orderInfo.orderHash,
                uint8(orderInfo.status)
            ).rrevert();
        }

        // Must be fillable by the taker.
        if (params.order.taker != address(0) && params.order.taker != params.taker) {
            LibNativeOrdersRichErrors.OrderNotFillableByTakerError(
                orderInfo.orderHash,
                params.taker,
                params.order.taker
            ).rrevert();
        }

        // Must be fillable by the sender.
        if (params.order.sender != address(0) && params.order.sender != params.sender) {
            LibNativeOrdersRichErrors.OrderNotFillableBySenderError(
                orderInfo.orderHash,
                params.sender,
                params.order.sender
            ).rrevert();
        }

        // Signature must be valid for the order.
        {
            address signer = LibSignature.getSignerOfHash(
                orderInfo.orderHash,
                params.signature
            );
            if (signer != params.order.maker) {
                LibNativeOrdersRichErrors.OrderNotSignedByMakerError(
                    orderInfo.orderHash,
                    signer,
                    params.order.maker
                ).rrevert();
            }
        }

        // Pay the protocol fee.
        results.ethProtocolFeePaid = _collectProtocolFee(params.order.pool);

        // Settle between the maker and taker.
        (results.takerTokenFilledAmount, results.makerTokenFilledAmount) = _settleOrder(
            SettleOrderInfo({
                orderHash: orderInfo.orderHash,
                maker: params.order.maker,
                taker: params.taker,
                makerToken: IERC20TokenV06(params.order.makerToken),
                takerToken: IERC20TokenV06(params.order.takerToken),
                makerAmount: params.order.makerAmount,
                takerAmount: params.order.takerAmount,
                takerTokenFillAmount: params.takerTokenFillAmount,
                takerTokenFilledAmount: orderInfo.takerTokenFilledAmount
            })
        );

        // Pay the fee recipient.
        if (params.order.takerTokenFeeAmount > 0) {
            results.takerTokenFeeFilledAmount = uint128(LibMathV06.getPartialAmountFloor(
                results.takerTokenFilledAmount,
                params.order.takerAmount,
                params.order.takerTokenFeeAmount
            ));
            _transferERC20Tokens(
                params.order.takerToken,
                params.taker,
                params.order.feeRecipient,
                uint256(results.takerTokenFeeFilledAmount)
            );
        }

        emit LimitOrderFilled(
            orderInfo.orderHash,
            params.order.maker,
            params.taker,
            params.order.feeRecipient,
            address(params.order.makerToken),
            address(params.order.takerToken),
            results.takerTokenFilledAmount,
            results.makerTokenFilledAmount,
            results.takerTokenFeeFilledAmount,
            results.ethProtocolFeePaid,
            params.order.pool
        );
    }

    /// @dev Fill an RFQ order. Private variant. Does not refund protocol fees.
    /// @param order The RFQ order.
    /// @param signature The order signature.
    /// @param takerTokenFillAmount Maximum taker token to fill this order with.
    /// @param taker The order taker.
    /// @return results Results of the fill.
    function _fillRfqOrderPrivate(
        LibNativeOrder.RfqOrder memory order,
        LibSignature.Signature memory signature,
        uint128 takerTokenFillAmount,
        address taker
    )
        private
        returns (FillNativeOrderResults memory results)
    {
        LibNativeOrder.OrderInfo memory orderInfo = getRfqOrderInfo(order);

        // Must be fillable.
        if (orderInfo.status != LibNativeOrder.OrderStatus.FILLABLE) {
            LibNativeOrdersRichErrors.OrderNotFillableError(
                orderInfo.orderHash,
                uint8(orderInfo.status)
            ).rrevert();
        }

        {
            LibNativeOrdersStorage.Storage storage stor =
                LibNativeOrdersStorage.getStorage();

            // Must be fillable by the tx.origin.
            if (order.txOrigin != tx.origin && !stor.originRegistry[order.txOrigin][tx.origin]) {
                LibNativeOrdersRichErrors.OrderNotFillableByOriginError(
                    orderInfo.orderHash,
                    tx.origin,
                    order.txOrigin
                ).rrevert();
            }
        }

        // Must be fillable by the taker.
        if (order.taker != address(0) && order.taker != taker) {
            LibNativeOrdersRichErrors.OrderNotFillableByTakerError(
                orderInfo.orderHash,
                taker,
                order.taker
            ).rrevert();
        }

        // Signature must be valid for the order.
        {
            address signer = LibSignature.getSignerOfHash(orderInfo.orderHash, signature);
            if (signer != order.maker) {
                LibNativeOrdersRichErrors.OrderNotSignedByMakerError(
                    orderInfo.orderHash,
                    signer,
                    order.maker
                ).rrevert();
            }
        }

        // Settle between the maker and taker.
        (results.takerTokenFilledAmount, results.makerTokenFilledAmount) = _settleOrder(
            SettleOrderInfo({
                orderHash: orderInfo.orderHash,
                maker: order.maker,
                taker: taker,
                makerToken: IERC20TokenV06(order.makerToken),
                takerToken: IERC20TokenV06(order.takerToken),
                makerAmount: order.makerAmount,
                takerAmount: order.takerAmount,
                takerTokenFillAmount: takerTokenFillAmount,
                takerTokenFilledAmount: orderInfo.takerTokenFilledAmount
            })
        );

        emit RfqOrderFilled(
            orderInfo.orderHash,
            order.maker,
            taker,
            address(order.makerToken),
            address(order.takerToken),
            results.takerTokenFilledAmount,
            results.makerTokenFilledAmount,
            order.pool
        );
    }

    /// @dev Settle the trade between an order's maker and taker.
    /// @param settleInfo Information needed to execute the settlement.
    /// @return takerTokenFilledAmount How much taker token was filled.
    /// @return makerTokenFilledAmount How much maker token was filled.
    function _settleOrder(SettleOrderInfo memory settleInfo)
        private
        returns (uint128 takerTokenFilledAmount, uint128 makerTokenFilledAmount)
    {
        // Clamp the taker token fill amount to the fillable amount.
        takerTokenFilledAmount = LibSafeMathV06.min128(
            settleInfo.takerTokenFillAmount,
            settleInfo.takerAmount.safeSub128(settleInfo.takerTokenFilledAmount)
        );
        // Compute the maker token amount.
        // This should never overflow because the values are all clamped to
        // (2^128-1).
        makerTokenFilledAmount = uint128(LibMathV06.getPartialAmountFloor(
            uint256(takerTokenFilledAmount),
            uint256(settleInfo.takerAmount),
            uint256(settleInfo.makerAmount)
        ));

        if (takerTokenFilledAmount == 0 || makerTokenFilledAmount == 0) {
            // Nothing to do.
            return (0, 0);
        }

        // Update filled state for the order.
        LibNativeOrdersStorage
            .getStorage()
            .orderHashToTakerTokenFilledAmount[settleInfo.orderHash] =
            // OK to overwrite the whole word because we shouldn't get to this
            // function if the order is cancelled.
                settleInfo.takerTokenFilledAmount.safeAdd128(takerTokenFilledAmount);

        // Transfer taker -> maker.
        _transferERC20Tokens(
            settleInfo.takerToken,
            settleInfo.taker,
            settleInfo.maker,
            takerTokenFilledAmount
        );

        // Transfer maker -> taker.
        _transferERC20Tokens(
            settleInfo.makerToken,
            settleInfo.maker,
            settleInfo.taker,
            makerTokenFilledAmount
        );
    }
}
