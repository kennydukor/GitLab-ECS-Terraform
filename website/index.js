const nunjucks = require('nunjucks')
const express = require('express')
const axios = require('axios')

const PORT = process.env.PORT || 80

const app = express()

nunjucks.configure("views", {
    express: app,
    autoescape: false,
    noCache: true
})

app.set('view engine', 'njk')

app.use(express.static('public'))

app.locals.version = require('./package.json').version

app.get('/', async (req, res) => {
    try {
        const url = process.env.NODE_ENV == 'development'
            ? `http://127.0.0.1:${PORT}/js/metadata.json`
            : 'http://169.254.170.2/v2/metadata'
        const result = await axios.get(url)

        const container = result.data.Containers.find(e => e.Image.includes('tinyproxy') == false)

        res.render('index', {
            url,
            data: JSON.stringify(result.data, null, 2),
            image: container.Image,
            network: container.Networks[0].NetworkMode,
            address: container.Networks[0].IPv4Addresses[0]

        })
    } catch (err) {
        return res.json({
            code: err.code, 
            message: err.message
        })
    }
})

app.listen(PORT, () => {
    console.log(`listening on port ${PORT}`)
})
