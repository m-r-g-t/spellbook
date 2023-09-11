{{ config (
    alias = alias('etv_addliquiditytoJob')
    , unique_key = ['blockchain', 'block_time']
    , post_hook = '{{ expose_spells(\'["ethereum", "optimism", "polygon"]\',
                                "project", 
                                "keep3r",
                                 \'["0xr3x"]\') }}'
) }}
   SELECT
      call_block_time as block_time,
      CAST(amount as double) / 1e18 as amount,
      job,
      liquidity,
      'addLiquidityToJob' as event,
      'ethereum' as blockchain
    FROM
        {{ source(
            'keep3r_network_ethereum',
            'Keep3rV1_call_addLiquidityToJob'
        ) }}
    WHERE
      call_success = true
    UNION ALL
    SELECT
      call_block_time as block_time,
      CAST(_amount as double) / 1e18 as amount,
      _job as job,
      _liquidity as liquidity,
      'addLiquidityToJob' as event,
      'ethereum' as blockchain
    FROM
        { source(
            'keep3r_network_ethereum',
            'Keep3r_v2_call_addLiquidityToJob'
        ) }}
    WHERE
      call_success = TRUE
    UNION ALL
    SELECT
      call_block_time as block_time,
      CAST(_amount as double) / 1e18 as amount,
      _job as job,
      _liquidity as liquidity,
      'addLiquidityToJob' as event,
      'optimism' as blockchain
    FROM
        { source(
            'keep3r_network_optimism',
            'Keep3rSidechain_call_addLiquidityToJob'
        ) }}
    WHERE
      call_success = TRUE    
    UNION ALL
    SELECT
      call_block_time as block_time,
      CAST(_amount as double) / 1e18 as amount,
      _job as job,
      _liquidity as liquidity,
      'addLiquidityToJob' as event,
      'polygon' as blockchain
    FROM
        { source(
            'keep3r_network_polygon',
            'Keep3rSidechain_call_addLiquidityToJob'
        ) }}
    WHERE
      call_success = TRUE 