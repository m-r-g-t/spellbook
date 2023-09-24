{{  config(
        alias = alias('batches'),
        tags = ['dunesql'],
        materialized='incremental',
        partition_by = ['block_date'],
        unique_key = ['tx_hash'],
        on_schema_change='sync_all_columns',
        file_format ='delta',
        incremental_strategy='merge',
        post_hook='{{ expose_spells(\'["gnosis"]\',
                                    "project",
                                    "cow_protocol",
                                    \'["bh2smith"]\') }}'
    )
}}

WITH
-- Find the PoC Query here: https://dune.com/queries/1722419
batch_counts as (
    select try_cast(date_trunc('day', s.evt_block_time) as date) as block_date,
           s.evt_block_time,
           s.evt_tx_hash,
           solver,
           name,
           sum(
               case
                   when selector != 0x2e1a7d4d -- unwrap
                    and selector != 0x095ea7b3 -- approval
                       then 1
                   else 0
                end)                                                as dex_swaps,
           sum(case when selector = 0x2e1a7d4d then 1 else 0 end) as unwraps,
           sum(case when selector = 0x095ea7b3 then 1 else 0 end) as token_approvals
    from {{ source('gnosis_protocol_v2_gnosis', 'GPv2Settlement_evt_Settlement') }} s
        left outer join {{ source('gnosis_protocol_v2_gnosis', 'GPv2Settlement_evt_Interaction') }} i
            on i.evt_tx_hash = s.evt_tx_hash
            {% if is_incremental() %}
            AND i.evt_block_time >= date_trunc('day', now() - interval '7' day)
            {% endif %}
        join cow_protocol_gnosis.solvers
            on solver = address
    {% if is_incremental() %}
    WHERE s.evt_block_time >= date_trunc('day', now() - interval '7' day)
    {% endif %}
    group by s.evt_tx_hash, solver, s.evt_block_time, name
),

batch_values as (
    select
        tx_hash,
        count(*)        as num_trades,
        sum(usd_value)  as batch_value,
        sum(fee_usd)    as fee_value,
        price           as eth_price
    from {{ ref('cow_protocol_gnosis_trades') }}
        left outer join {{ source('prices', 'usd') }} as p
            on p.contract_address = 0xe91d153e0b41518a2ce8dd3d7944fa863463a97d
            and p.minute = date_trunc('minute', block_time)
            and blockchain = 'gnosis'
    {% if is_incremental() %}
    WHERE block_time >= date_trunc('day', now() - interval '7' day)
    {% endif %}
    group by tx_hash, price
),

combined_batch_info as (
    select
        b.block_date,
        evt_block_time                                 as block_time,
        num_trades,
        dex_swaps,
        batch_value,
        solver                                           as solver_address,
        evt_tx_hash                                      as tx_hash,
        gas_price,
        gas_used,
        ((gas_price / pow(10, 9)) * gas_used * eth_price) / pow(10, 9) as tx_cost_usd,
        fee_value,
        2 * bytearray_length(data) / 1024                     as call_data_size,
        unwraps,
        token_approvals
    from batch_counts b
        join batch_values t
            on b.evt_tx_hash = t.tx_hash
        inner join {{ source('gnosis', 'transactions') }} tx
            on evt_tx_hash = hash
            {% if is_incremental() %}
            AND tx.block_time >= date_trunc('day', now() - interval '7' day)
            {% endif %}
    where num_trades > 0 --! Exclude Withdraw Batches
)

select * from combined_batch_info
