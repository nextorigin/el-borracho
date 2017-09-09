# el-borracho

[![Greenkeeper badge](https://badges.greenkeeper.io/nextorigin/el-borracho.svg)](https://greenkeeper.io/)

[![Build Status][ci-master]][travis-ci]
[![Coverage Status][coverage-master]][coveralls]
[![Dependency Status][dependency]][david]
[![devDependency Status][dev-dependency]][david-dev]
[![Downloads][downloads]][npm]

Express 4 router containing a REST and SSE API for Bull job queues, based heavily on [express-bull][express-bull] and [Matador](https://github.com/ShaneK/Matador). It uses less libraries and uses Iced Coffeescript instead of bluebird for async handling.

Designed for consumption by [el-borracho-ui][el-borracho-ui]

[![NPM][npm-stats]][npm]

## Installation
```sh
npm install --save el-borracho
```

## License

MIT

  [express-bull]:  https://github.com/kfatehi/express-bull
  [el-borracho-ui]:  https://github.com/nextorigin/el-borracho-ui

  [ci-master]: https://img.shields.io/travis/nextorigin/el-borracho/master.svg?style=flat-square
  [travis-ci]: https://travis-ci.org/nextorigin/el-borracho
  [coverage-master]: https://img.shields.io/coveralls/nextorigin/el-borracho/master.svg?style=flat-square
  [coveralls]: https://coveralls.io/r/nextorigin/el-borracho
  [dependency]: https://img.shields.io/david/nextorigin/el-borracho.svg?style=flat-square
  [david]: https://david-dm.org/nextorigin/el-borracho
  [dev-dependency]: https://img.shields.io/david/dev/nextorigin/el-borracho.svg?style=flat-square
  [david-dev]: https://david-dm.org/nextorigin/el-borracho?type=dev
  [downloads]: https://img.shields.io/npm/dm/el-borracho.svg?style=flat-square
  [npm]: https://www.npmjs.org/package/el-borracho
  [npm-stats]: https://nodei.co/npm/el-borracho.png?downloads=true&downloadRank=true&stars=true
