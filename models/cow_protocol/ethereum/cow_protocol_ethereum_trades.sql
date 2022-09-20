{{  config(
        alias='trades',
        materialized='incremental',
        unique_key = ['tx_hash', 'order_uid'],
        on_schema_change='fail',
        file_format ='delta',
        incremental_strategy='merge'
    )
}}

-- Find the PoC Query here: https://dune.com/queries/1283229
WITH
-- First subquery joins buy and sell token prices from prices.usd.
-- Also deducts fee from sell amount.
trades_with_prices AS (
    SELECT evt_block_time            as block_time,
           evt_tx_hash               as tx_hash,
           owner                     as trader,
           orderUid                  as order_uid,
           sellToken                 as sell_token,
           buyToken                  as buy_token,
           (sellAmount - feeAmount)  as sell_amount,
           buyAmount                 as buy_amount,
           feeAmount                 as fee_amount,
           ps.price                  as sell_price,
           pb.price                  as buy_price
    FROM {{ source('gnosis_protocol_v2_ethereum', 'GPv2Settlement_evt_Trade') }}
             LEFT OUTER JOIN {{ source('prices', 'usd') }} as ps
                             ON sellToken = ps.contract_address
                                 AND ps.minute = date_trunc('minute', evt_block_time)
                                 AND ps.blockchain = 'ethereum'
             LEFT OUTER JOIN {{ source('prices', 'usd') }} as pb
                             ON pb.contract_address = (
                                 CASE
                                     WHEN buyToken = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
                                         THEN '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
                                     ELSE buyToken
                                     END)
                                 AND pb.minute = date_trunc('minute', evt_block_time)
                                 AND pb.blockchain = 'ethereum'
    {% if is_incremental() %}
    WHERE evt_block_time >= date_trunc("day", now() - interval '1 week')
    {% endif %}
),
-- Second subquery gets token symbol and decimals from tokens.erc20 (to display units bought and sold)
trades_with_token_units as (
    SELECT block_time,
           tx_hash,
           order_uid,
           trader,
           sell_token                        as sell_token_address,
           (CASE
                WHEN ts.symbol IS NULL THEN sell_token
                ELSE ts.symbol
               END)                          as sell_token,
           buy_token                         as buy_token_address,
           (CASE
                WHEN tb.symbol IS NULL THEN buy_token
                WHEN buy_token = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN 'ETH'
                ELSE tb.symbol
               END)                          as buy_token,
           sell_amount / pow(10, ts.decimals) as units_sold,
           sell_amount                       as atoms_sold,
           buy_amount / pow(10, tb.decimals)  as units_bought,
           buy_amount                        as atoms_bought,
           -- We use sell value when possible and buy value when not
           fee_amount / pow(10, ts.decimals)  as fee,
           fee_amount                        as fee_atoms,
           sell_price,
           buy_price
    FROM trades_with_prices
             LEFT OUTER JOIN {{ ref('tokens_ethereum_erc20') }} ts
                             ON ts.contract_address = sell_token
             LEFT OUTER JOIN {{ ref('tokens_ethereum_erc20') }} tb
                             ON tb.contract_address =
                                (CASE
                                     WHEN buy_token = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
                                         THEN '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
                                     ELSE buy_token
                                    END)
),
-- This, independent, aggregation defines a mapping of order_uid and trade
-- TODO - create a view for the following block mapping uid to app_data
order_ids as (
    select evt_tx_hash, collect_list(orderUid) as order_ids
    from (  select orderUid, evt_tx_hash, evt_index
            from {{ source('gnosis_protocol_v2_ethereum', 'GPv2Settlement_evt_Trade') }}
                     sort by evt_index
         ) as _
    group by evt_tx_hash
),

exploded_order_ids as (
    select evt_tx_hash, posexplode(order_ids)
    from order_ids
),

reduced_order_ids as (
    select
        col as order_id,
        -- This is a dirty hack!
        collect_list(evt_tx_hash)[0] as evt_tx_hash,
        collect_list(pos)[0] as pos
    from exploded_order_ids
    group by order_id
),

trade_data as (
    select call_tx_hash,
           posexplode(trades)
    from {{ source('gnosis_protocol_v2_ethereum', 'GPv2Settlement_call_settle') }}
    where call_success = true
),

uid_to_app_id as (
    select
        order_id as uid,
        get_json_object(trades.col, '$.appData') as app_data,
        get_json_object(trades.col, '$.receiver') as receiver
    from reduced_order_ids order_ids
             join trade_data trades
                  on evt_tx_hash = call_tx_hash
                      and order_ids.pos = trades.pos
),

valued_trades as (
    SELECT block_time,
           tx_hash,
           order_uid,
           trader,
           sell_token_address,
           sell_token,
           buy_token_address,
           buy_token,
           case
                 when lower(buy_token) > lower(sell_token) then concat(sell_token, '-', buy_token)
                 else concat(buy_token, '-', sell_token)
               end as token_pair,
           units_sold,
           atoms_sold,
           units_bought,
           atoms_bought,
           (CASE
                WHEN sell_price IS NOT NULL THEN
                    -- Choose the larger of two prices when both not null.
                    CASE
                        WHEN buy_price IS NOT NULL and buy_price * units_bought > sell_price * units_sold
                            then buy_price * units_bought
                        ELSE sell_price * units_sold
                        END
                WHEN sell_price IS NULL AND buy_price IS NOT NULL THEN buy_price * units_bought
                ELSE NULL::numeric
               END)                                        as usd_value,
           buy_price,
           buy_price * units_bought                        as buy_value_usd,
           sell_price,
           sell_price * units_sold                         as sell_value_usd,
           fee,
           fee_atoms,
           (CASE
                WHEN sell_price IS NOT NULL THEN
                    CASE
                        WHEN buy_price IS NOT NULL and buy_price * units_bought > sell_price * units_sold
                            then buy_price * units_bought * fee / units_sold
                        ELSE sell_price * fee
                        END
                WHEN sell_price IS NULL AND buy_price IS NOT NULL
                    THEN buy_price * units_bought * fee / units_sold
                ELSE NULL::numeric
               END)                                        as fee_usd,
           app_data,
           receiver
    FROM trades_with_token_units
             JOIN uid_to_app_id
                  ON uid = order_uid
)

select * from valued_trades
