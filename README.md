## x-ui-pro (x-ui + nginx) modification of https://github.com/GFW4Fun/x-ui-pro for REALITY
- Auto Installation (lightweight)
- Auto SSL renewal / Daily reload Nginx X-ui
- Handle **REALITY** and **WebSocket** via **nginx**.
- Multi-user and config via port **443**
- Auto enabled subscriptions via port **443**
- Auto configured VLESS+Reality and VLESSoverWebSocket
- **Custom Web Sub Page**
- Feature that allows the use of **custom client configurations for SING-BOX & CLASH META**
- **Local instance sub2sing-box**
- Auto configured Firewall
- More security and low detection with nginx
- Compatible with Cloudflare (only for WebSocket/GRPC)
- Random 150+ fake template!
- Linux Debian12/Ubuntu24!


  **You need TWO domains or subdomains**
  1. For panel and WebSocket/GRPC/HttpUgrade/SplitHttp
  2. For REALITY destination
  >
  Get Free subdomains - https://scarce-hole-1e2.notion.site/14d1666462e48069818cf42553bfae1f?pvs=74
  >
  RU instruction - https://scarce-hole-1e2.notion.site/3X-UI-pro-with-REALITY-panel-and-inbaunds-on-port-443-10d1666462e48085be0fee4c136ce417
  
➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖
### Install X-UI-PRO motor2hg
```
bash <(curl -LsS https://github.com/motor2hg/x-ui-pro/raw/master/x-ui-pro.sh) -install y -panel 1 -ONLY_CF_IP_ALLOW n
```
or with wget:
```
bash <(wget -qO- https://github.com/motor2hg/x-ui-pro/raw/master/x-ui-pro.sh) -install y -panel 1 -ONLY_CF_IP_ALLOW n
```


> Do not change SubDomain after install, otherwise SSL renewal will fail!

### Uninstall X-UI-PRO

```
bash <(curl -LsS https://github.com/motor2hg/x-ui-pro/raw/master/x-ui-pro.sh) -uninstall y
```

➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖➖
### Screenshots :wrench:🐧⚙️
>
**How to open custom web sub page?**
>
![](https://github.com/legiz-ru/x-ui-pro/blob/master/media/CustomWebSubHow2Open.png?raw=true)
>
**Main Page custom web sub**
>
![](https://github.com/legiz-ru/x-ui-pro/blob/master/media/CustomWebSub.png?raw=true)
>
**sub2sing-box section on custom web sub page**
>
![](https://github.com/legiz-ru/x-ui-pro/blob/master/media/CustomWebSubSingBox.png?raw=true)
>
**local instance sub2sing-box fork by legiz**
>
![](https://github.com/legiz-ru/x-ui-pro/blob/master/media/sub2sing.png?raw=true)
