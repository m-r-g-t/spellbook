{{ config (
    tags=['dunesql']
    , alias = alias('etv_liquidity_addition')
<<<<<<< HEAD
=======
    , unique_key = ['blockchain', 'block_time']
>>>>>>> 2c873279 (feat: add liquidity addition and withdral queries)
    , post_hook = '{{ expose_spells(\'["ethereum", "optimism", "polygon"]\',
                                "project", 
                                "keep3r",
                                 \'["0xr3x"]\') }}'
) }}


    SELECT
        evt_block_time,
        evt_tx_hash,
        evt_index,
        contract_address,
        _job,
        _liquidity,
        _amount,
        'ethereum' as blockchain
    FROM
      {{ source(
        'keep3r_network_ethereum',
        'Keep3r_evt_LiquidityAddition'
      ) }}

    UNION
    SELECT
        evt_block_time,
        evt_tx_hash,
        evt_index,
        contract_address,
        _job,
        _liquidity,
        _amount,
        'ethereum' as blockchain
    FROM
      {{ source(
        'keep3r_network_ethereum',
        'Keep3r_v2_evt_LiquidityAddition'
      ) }}

    UNION
    SELECT
        evt_block_time,
        evt_tx_hash,
        evt_index,
        contract_address,
        _job,
        _liquidity,
        _amount,
        'optimism' as blockchain
    FROM
      {{ source(
        'keep3r_network_optimism',
        'Keep3rSidechain_evt_LiquidityAddition'
      ) }}
    UNION
    SELECT
        evt_block_time,
        evt_tx_hash,
        evt_index,
        contract_address,
        _job,
        _liquidity,
        _amount,
        'polygon' as blockchain
    FROM
            {{ source(
        'keep3r_network_polygon',
        'Keep3rSidechain_evt_LiquidityAddition'
    ) }}