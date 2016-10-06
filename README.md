# el-borracho

Express 4 router containing a REST and SSE API for Bull job queues, based heavily on [express-bull][express-bull] and [Matador](https://github.com/ShaneK/Matador). It uses less libraries and uses Iced Coffeescript instead of bluebird for async handling.

Designed for consumption by [el-borracho-ui][el-borracho-ui]

## Installation
```sh
npm install --save el-borracho
```

## License

MIT

  [express-bull]:  https://github.com/kfatehi/express-bull
  [el-borracho-ui]:  https://github.com/nextorigin/el-borracho-ui