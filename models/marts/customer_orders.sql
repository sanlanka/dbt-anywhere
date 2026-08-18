{{ config(materialized='table') }}

with customers as (

    select * from {{ ref('stg_customers') }}

),

orders as (

    select * from {{ ref('stg_orders') }}
    where status = 'completed'

),

order_totals as (

    select
        customer_id,
        count(*)          as completed_orders,
        sum(amount)       as lifetime_value,
        min(order_date)   as first_order_date,
        max(order_date)   as most_recent_order_date

    from orders
    group by customer_id

)

select
    c.customer_id,
    c.full_name,
    c.signup_date,
    coalesce(t.completed_orders, 0) as completed_orders,
    coalesce(t.lifetime_value, 0)   as lifetime_value,
    t.first_order_date,
    t.most_recent_order_date

from customers as c
left join order_totals as t on c.customer_id = t.customer_id
